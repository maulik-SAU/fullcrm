/**
 * Handler: SAU_QuoteLineItemTriggerHandler
 * Purpose:
 *  (1) Enforce per-line Min/Max quantity on the QuoteLineItem trigger.
 *  (2) Track the lines touched in the current save (recordTouched) and compute
 *      bundle component-group violations for the bundle(s) being saved
 *      (getTouchedBundleViolations). This counts the lines BEING SAVED in this
 *      transaction rather than the deferred ParentQuoteLineItemId links, so it
 *      is accurate at Save & Exit (no false blocks from incomplete linking) and
 *      naturally scoped to the configured bundle (leftovers don't interfere).
 *      The Quote trigger calls it when the save/recalc completes.
 *  (3) getBundleCardinalityViolations: whole-quote check used at the finalize
 *      checkpoint as a backstop.
 */
public with sharing class SAU_QuoteLineItemTriggerHandler {

    // Lines touched in the current save transaction (populated by the QLI trigger).
    public static Set<Id> touchedQliIds = new Set<Id>();

    /** Record changed line Ids so the configured bundle can be validated at save completion. */
    public static void recordTouched(List<QuoteLineItem> changed) {
        if (changed == null) return;
        for (QuoteLineItem q : changed) {
            if (q.Id != null) touchedQliIds.add(q.Id);
        }
    }

    public static void validateQuantityLimits(List<QuoteLineItem> qlis) {
        if (qlis == null || qlis.isEmpty()) return;

        Set<Id> qliIds     = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        for (QuoteLineItem qli : qlis) {
            if (qli.Id != null)         qliIds.add(qli.Id);
            if (qli.Product2Id != null) productIds.add(qli.Product2Id);
        }

        Map<Id, QuoteLineRelationship> qliToRelation = new Map<Id, QuoteLineRelationship>();
        Set<Id> prcIdsFromRel = new Set<Id>();
        if (!qliIds.isEmpty()) {
            for (QuoteLineRelationship rel : [
                SELECT Id, AssociatedQuoteLineId, MainQuoteLineId, ProductRelatedComponentId
                FROM QuoteLineRelationship
                WHERE AssociatedQuoteLineId IN :qliIds
            ]) {
                qliToRelation.put(rel.AssociatedQuoteLineId, rel);
                if (rel.ProductRelatedComponentId != null) {
                    prcIdsFromRel.add(rel.ProductRelatedComponentId);
                }
            }
        }

        Map<Id, ProductRelatedComponent> prcByIdMap = new Map<Id, ProductRelatedComponent>();
        if (!prcIdsFromRel.isEmpty()) {
            prcByIdMap = new Map<Id, ProductRelatedComponent>([
                SELECT Id, MinQuantity, MaxQuantity, ChildProductId
                FROM ProductRelatedComponent WHERE Id IN :prcIdsFromRel
            ]);
        }

        // A bundle component's quantity limits come from the SPECIFIC bundle it
        // belongs to (resolved via ParentQuoteLineItemId) — the same component can
        // have different limits in different bundles (e.g. 3.84TB NVMe has no min
        // in Enterprise 16 but min 2 in Enterprise 24). A catalog-wide lookup
        // would wrongly apply the strictest limit across all bundles.
        Set<Id> parentQliIds = new Set<Id>();
        for (QuoteLineItem qli : qlis) {
            if (qli.ParentQuoteLineItemId != null) parentQliIds.add(qli.ParentQuoteLineItemId);
        }
        Map<Id, Id> parentQliToProduct = new Map<Id, Id>();
        if (!parentQliIds.isEmpty()) {
            for (QuoteLineItem p : [SELECT Id, Product2Id FROM QuoteLineItem WHERE Id IN :parentQliIds]) {
                parentQliToProduct.put(p.Id, p.Product2Id);
            }
        }
        Map<String, ProductRelatedComponent> prcByParentChild = new Map<String, ProductRelatedComponent>();
        if (!parentQliToProduct.isEmpty() && !productIds.isEmpty()) {
            Set<Id> parentProductIds = new Set<Id>(parentQliToProduct.values());
            for (ProductRelatedComponent prc : [
                SELECT Id, MinQuantity, MaxQuantity, ChildProductId, ParentProductId
                FROM ProductRelatedComponent
                WHERE ParentProductId IN :parentProductIds AND ChildProductId IN :productIds
            ]) {
                prcByParentChild.put(prc.ParentProductId + '|' + prc.ChildProductId, prc);
            }
        }

        Map<Id, Product2> productMap = new Map<Id, Product2>();
        if (!productIds.isEmpty()) {
            productMap = new Map<Id, Product2>([
                SELECT Id, Name, SAU_Min_Quantity__c, SAU_Max_Quantity__c
                FROM Product2 WHERE Id IN :productIds
            ]);
        }

        for (QuoteLineItem qli : qlis) {
            if (qli.Quantity == null) continue;
            Decimal minQty; Decimal maxQty; String source;
            QuoteLineRelationship rel = qliToRelation.get(qli.Id);
            if (rel != null && rel.ProductRelatedComponentId != null && prcByIdMap.containsKey(rel.ProductRelatedComponentId)) {
                ProductRelatedComponent prc = prcByIdMap.get(rel.ProductRelatedComponentId);
                minQty = prc.MinQuantity; maxQty = prc.MaxQuantity; source = 'bundle component';
            } else if (qli.ParentQuoteLineItemId != null
                       && parentQliToProduct.containsKey(qli.ParentQuoteLineItemId)
                       && prcByParentChild.containsKey(parentQliToProduct.get(qli.ParentQuoteLineItemId) + '|' + qli.Product2Id)) {
                ProductRelatedComponent prc = prcByParentChild.get(parentQliToProduct.get(qli.ParentQuoteLineItemId) + '|' + qli.Product2Id);
                minQty = prc.MinQuantity; maxQty = prc.MaxQuantity; source = 'bundle component';
            } else if (qli.Product2Id != null && productMap.containsKey(qli.Product2Id)) {
                Product2 prod = productMap.get(qli.Product2Id);
                minQty = prod.SAU_Min_Quantity__c; maxQty = prod.SAU_Max_Quantity__c; source = 'standalone product';
            }
            if (minQty == null && maxQty == null) continue;
            String prodName = (qli.Product2Id != null && productMap.containsKey(qli.Product2Id)) ? productMap.get(qli.Product2Id).Name : '';
            if (minQty != null && qli.Quantity < minQty) {
                qli.Quantity.addError(prodName + ' ' + 'Quantity (' + qli.Quantity + ') is below the allowed minimum of ' + minQty + '. Please update the quantity to proceed.');
            }
            if (maxQty != null && qli.Quantity > maxQty) {
                qli.Quantity.addError(prodName + ' ' + 'Quantity (' + qli.Quantity + ') exceeds the allowed maximum of ' + maxQty + '. Please update the quantity to proceed.');
            }
        }
    }

    /**
     * Returns, per quote, the list of bundle component-group cardinality
     * violation messages. Counts the number of DISTINCT component lines per
     * group, per individual bundle instance. Child -> parent is resolved from
     * QuoteLineItem.ParentQuoteLineItemId (the structural link) and, as a
     * fallback, QuoteLineRelationship. Intended to run on a fully-settled quote
     * (e.g. at a status checkpoint), where these links are reliably present.
     */
    public static Map<Id, List<String>> getBundleCardinalityViolations(Set<Id> quoteIds) {
        return getBundleCardinalityViolations(quoteIds, null);
    }

    /**
     * @param scopeParentQliIds  if non-null and non-empty, only these bundle
     *        parent lines are validated (used to scope to the bundle being
     *        configured); if null, every bundle on the quote(s) is checked.
     */
    public static Map<Id, List<String>> getBundleCardinalityViolations(Set<Id> quoteIds, Set<Id> scopeParentQliIds) {
        Map<Id, List<String>> result = new Map<Id, List<String>>();
        if (quoteIds == null || quoteIds.isEmpty()) return result;
        Boolean scoped = (scopeParentQliIds != null && !scopeParentQliIds.isEmpty());

        // Bundle parent lines on the quote(s).
        Map<Id, Id> bundleParentToProduct = new Map<Id, Id>();
        Map<Id, Id> bundleParentToQuote   = new Map<Id, Id>();
        Set<Id> bundleProductIds = new Set<Id>();
        for (QuoteLineItem bp : [
            SELECT Id, QuoteId, Product2Id FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds AND Product2.Type = 'Bundle'
        ]) {
            bundleParentToProduct.put(bp.Id, bp.Product2Id);
            bundleParentToQuote.put(bp.Id, bp.QuoteId);
            bundleProductIds.add(bp.Product2Id);
        }
        if (bundleProductIds.isEmpty()) return result;

        // Constrained groups for those bundle products.
        Map<Id, List<ProductComponentGroup>> productToGroups = new Map<Id, List<ProductComponentGroup>>();
        Set<Id> allGroupIds = new Set<Id>();
        for (ProductComponentGroup pcg : [
            SELECT Id, Name, ParentProductId, ParentProduct.Name, MinBundleComponents, MaxBundleComponents
            FROM ProductComponentGroup
            WHERE ParentProductId IN :bundleProductIds
              AND (MinBundleComponents != null OR MaxBundleComponents != null)
        ]) {
            if (!productToGroups.containsKey(pcg.ParentProductId)) {
                productToGroups.put(pcg.ParentProductId, new List<ProductComponentGroup>());
            }
            productToGroups.get(pcg.ParentProductId).add(pcg);
            allGroupIds.add(pcg.Id);
        }
        if (allGroupIds.isEmpty()) return result;

        // Which catalog child products belong to which constrained group.
        Map<Id, Set<Id>> childProductToGroups = new Map<Id, Set<Id>>();
        for (ProductRelatedComponent prc : [
            SELECT ChildProductId, ProductComponentGroupId
            FROM ProductRelatedComponent WHERE ProductComponentGroupId IN :allGroupIds
        ]) {
            if (!childProductToGroups.containsKey(prc.ChildProductId)) {
                childProductToGroups.put(prc.ChildProductId, new Set<Id>());
            }
            childProductToGroups.get(prc.ChildProductId).add(prc.ProductComponentGroupId);
        }

        // Child lines on the quote(s).
        List<QuoteLineItem> childLines = [
            SELECT Id, Product2Id, ParentQuoteLineItemId
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
              AND Product2Id != null
              AND Product2.Type != 'Bundle'
        ];

        // child line -> its bundle parent line (ParentQuoteLineItemId first,
        // QuoteLineRelationship as fallback).
        Map<Id, Id> childToParent = new Map<Id, Id>();
        for (QuoteLineItem child : childLines) {
            if (child.ParentQuoteLineItemId != null
                && bundleParentToProduct.containsKey(child.ParentQuoteLineItemId)) {
                childToParent.put(child.Id, child.ParentQuoteLineItemId);
            }
        }
        for (QuoteLineRelationship rel : [
            SELECT AssociatedQuoteLineId, MainQuoteLineId
            FROM QuoteLineRelationship
            WHERE MainQuoteLineId IN :bundleParentToProduct.keySet()
        ]) {
            if (rel.AssociatedQuoteLineId != null && rel.MainQuoteLineId != null
                && !childToParent.containsKey(rel.AssociatedQuoteLineId)) {
                childToParent.put(rel.AssociatedQuoteLineId, rel.MainQuoteLineId);
            }
        }

        // parent line -> (group -> set of distinct child lines).
        Map<Id, Map<Id, Set<Id>>> parentToGroupChildren = new Map<Id, Map<Id, Set<Id>>>();
        Set<Id> configuredParents = new Set<Id>();
        for (QuoteLineItem child : childLines) {
            Id pq = childToParent.get(child.Id);
            if (pq == null || !bundleParentToProduct.containsKey(pq)) continue;
            configuredParents.add(pq);
            Set<Id> grpIds = childProductToGroups.get(child.Product2Id);
            if (grpIds == null) continue;
            List<ProductComponentGroup> groups = productToGroups.get(bundleParentToProduct.get(pq));
            if (groups == null) continue;
            if (!parentToGroupChildren.containsKey(pq)) parentToGroupChildren.put(pq, new Map<Id, Set<Id>>());
            for (ProductComponentGroup pcg : groups) {
                if (grpIds.contains(pcg.Id)) {
                    if (!parentToGroupChildren.get(pq).containsKey(pcg.Id)) {
                        parentToGroupChildren.get(pq).put(pcg.Id, new Set<Id>());
                    }
                    parentToGroupChildren.get(pq).get(pcg.Id).add(child.Id);
                }
            }
        }

        for (Id pq : bundleParentToProduct.keySet()) {
            // When scoping, only validate the bundle(s) being configured.
            if (scoped && !scopeParentQliIds.contains(pq)) continue;
            // A bundle with no children at all is treated as not-configured and
            // skipped (defensive); a configured bundle is fully checked.
            if (!configuredParents.contains(pq)) continue;
            List<ProductComponentGroup> groups = productToGroups.get(bundleParentToProduct.get(pq));
            if (groups == null) continue;
            Map<Id, Set<Id>> grpChildren = parentToGroupChildren.get(pq);

            for (ProductComponentGroup pcg : groups) {
                Integer count = (grpChildren != null && grpChildren.containsKey(pcg.Id))
                                ? grpChildren.get(pcg.Id).size() : 0;
                String msg;
                if (pcg.MinBundleComponents != null && count < pcg.MinBundleComponents) {
                    msg = pcg.ParentProduct.Name + ', ' + pcg.Name +
                          ' has min value ' + pcg.MinBundleComponents +
                          ' and you have added ' + count +
                          '. Please configure the ' + pcg.Name + ' to continue.';
                } else if (pcg.MaxBundleComponents != null && count > pcg.MaxBundleComponents) {
                    msg = pcg.ParentProduct.Name + ', ' + pcg.Name +
                          ' has max value ' + pcg.MaxBundleComponents +
                          ' and you have added ' + count +
                          '. Please configure the ' + pcg.Name + ' to continue.';
                }
                if (msg == null) continue;
                Id qId = bundleParentToQuote.get(pq);
                if (!result.containsKey(qId)) result.put(qId, new List<String>());
                result.get(qId).add(msg);
            }
        }
        return result;
    }

    /**
     * Validate the bundle(s) being saved in THIS transaction by counting the
     * touched lines (the parent + its children, which are all inserted before
     * RLM finishes linking them). Returns per-quote violation messages. This is
     * accurate at Save & Exit and scoped to the configured bundle, so it neither
     * false-blocks a valid bundle nor is affected by other/leftover bundles.
     */
    public static Map<Id, List<String>> getTouchedBundleViolations(Set<Id> touchedIds) {
        Map<Id, List<String>> result = new Map<Id, List<String>>();
        if (touchedIds == null || touchedIds.isEmpty()) return result;

        List<QuoteLineItem> touched = [
            SELECT Id, QuoteId, Product2Id, Product2.Type, ParentQuoteLineItemId
            FROM QuoteLineItem WHERE Id IN :touchedIds
        ];
        Map<Id, Id> bundleToProduct = new Map<Id, Id>();   // touched bundle parent QLI -> product
        Map<Id, Id> bundleToQuote   = new Map<Id, Id>();
        List<QuoteLineItem> children = new List<QuoteLineItem>();
        for (QuoteLineItem t : touched) {
            if (t.Product2.Type == 'Bundle') {
                bundleToProduct.put(t.Id, t.Product2Id);
                bundleToQuote.put(t.Id, t.QuoteId);
            } else if (t.Product2Id != null) {
                children.add(t);
            }
        }
        if (bundleToProduct.isEmpty()) return result;   // no bundle saved in this txn

        Set<Id> bundleProductIds = new Set<Id>(bundleToProduct.values());
        Map<Id, List<ProductComponentGroup>> productToGroups = new Map<Id, List<ProductComponentGroup>>();
        Set<Id> allGroupIds = new Set<Id>();
        for (ProductComponentGroup pcg : [
            SELECT Id, Name, ParentProductId, ParentProduct.Name, MinBundleComponents, MaxBundleComponents
            FROM ProductComponentGroup
            WHERE ParentProductId IN :bundleProductIds
              AND (MinBundleComponents != null OR MaxBundleComponents != null)
        ]) {
            if (!productToGroups.containsKey(pcg.ParentProductId)) {
                productToGroups.put(pcg.ParentProductId, new List<ProductComponentGroup>());
            }
            productToGroups.get(pcg.ParentProductId).add(pcg);
            allGroupIds.add(pcg.Id);
        }
        if (allGroupIds.isEmpty()) return result;

        Map<Id, Set<Id>> childProductToGroups = new Map<Id, Set<Id>>();
        for (ProductRelatedComponent prc : [
            SELECT ChildProductId, ProductComponentGroupId
            FROM ProductRelatedComponent WHERE ProductComponentGroupId IN :allGroupIds
        ]) {
            if (!childProductToGroups.containsKey(prc.ChildProductId)) {
                childProductToGroups.put(prc.ChildProductId, new Set<Id>());
            }
            childProductToGroups.get(prc.ChildProductId).add(prc.ProductComponentGroupId);
        }

        // Attribute touched children to a touched bundle: by ParentQuoteLineItemId
        // when linked, otherwise (single bundle being saved) to that one bundle.
        Id soleBundle = (bundleToProduct.size() == 1) ? new List<Id>(bundleToProduct.keySet())[0] : null;
        Map<Id, Map<Id, Set<Id>>> parentToGroupChildren = new Map<Id, Map<Id, Set<Id>>>();
        for (Id pq : bundleToProduct.keySet()) parentToGroupChildren.put(pq, new Map<Id, Set<Id>>());
        for (QuoteLineItem c : children) {
            Id pq = (c.ParentQuoteLineItemId != null && bundleToProduct.containsKey(c.ParentQuoteLineItemId))
                    ? c.ParentQuoteLineItemId : soleBundle;
            if (pq == null) continue;
            Set<Id> grpIds = childProductToGroups.get(c.Product2Id);
            if (grpIds == null) continue;
            List<ProductComponentGroup> groups = productToGroups.get(bundleToProduct.get(pq));
            if (groups == null) continue;
            for (ProductComponentGroup pcg : groups) {
                if (grpIds.contains(pcg.Id)) {
                    if (!parentToGroupChildren.get(pq).containsKey(pcg.Id)) {
                        parentToGroupChildren.get(pq).put(pcg.Id, new Set<Id>());
                    }
                    parentToGroupChildren.get(pq).get(pcg.Id).add(c.Id);
                }
            }
        }

        for (Id pq : bundleToProduct.keySet()) {
            List<ProductComponentGroup> groups = productToGroups.get(bundleToProduct.get(pq));
            if (groups == null) continue;
            Map<Id, Set<Id>> grpChildren = parentToGroupChildren.get(pq);
            for (ProductComponentGroup pcg : groups) {
                Integer count = (grpChildren != null && grpChildren.containsKey(pcg.Id)) ? grpChildren.get(pcg.Id).size() : 0;
                String msg;
                if (pcg.MinBundleComponents != null && count < pcg.MinBundleComponents) {
                    msg = pcg.ParentProduct.Name + ', ' + pcg.Name +
                          ' has min value ' + pcg.MinBundleComponents +
                          ' and you have added ' + count +
                          '. Please configure the ' + pcg.Name + ' to continue.';
                } else if (pcg.MaxBundleComponents != null && count > pcg.MaxBundleComponents) {
                    msg = pcg.ParentProduct.Name + ', ' + pcg.Name +
                          ' has max value ' + pcg.MaxBundleComponents +
                          ' and you have added ' + count +
                          '. Please configure the ' + pcg.Name + ' to continue.';
                }
                if (msg == null) continue;
                Id qId = bundleToQuote.get(pq);
                if (!result.containsKey(qId)) result.put(qId, new List<String>());
                result.get(qId).add(msg);
            }
        }
        return result;
    }
}
