/**
 * Handler: SAU_QuoteLineItemTriggerHandler
 * Purpose:
 *  (1) Enforce per-line Min/Max quantity (PRC relationship / fallback / standalone)
 *  (2) Enforce ProductComponentGroup cardinality across bundle children
 *      (insert / update / delete)
 */
public with sharing class SAU_QuoteLineItemTriggerHandler {

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

        Map<Id, ProductRelatedComponent> prcByChildProductMap = new Map<Id, ProductRelatedComponent>();
        if (!productIds.isEmpty()) {
            for (ProductRelatedComponent prc : [
                SELECT Id, MinQuantity, MaxQuantity, ChildProductId
                FROM ProductRelatedComponent WHERE ChildProductId IN :productIds
            ]) {
                ProductRelatedComponent existing = prcByChildProductMap.get(prc.ChildProductId);
                if (existing == null) {
                    prcByChildProductMap.put(prc.ChildProductId, prc);
                } else {
                    if (prc.MaxQuantity != null && (existing.MaxQuantity == null || prc.MaxQuantity < existing.MaxQuantity)) existing.MaxQuantity = prc.MaxQuantity;
                    if (prc.MinQuantity != null && (existing.MinQuantity == null || prc.MinQuantity > existing.MinQuantity)) existing.MinQuantity = prc.MinQuantity;
                }
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
            } else if (qli.Product2Id != null && prcByChildProductMap.containsKey(qli.Product2Id)) {
                ProductRelatedComponent prc = prcByChildProductMap.get(qli.Product2Id);
                minQty = prc.MinQuantity; maxQty = prc.MaxQuantity; source = 'bundle component (catalog limit)';
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

    public static void validateBundleProduct(List<QuoteLineItem> qlis, Boolean isDelete) {
        if (qlis == null || qlis.isEmpty()) return;

        if (isDelete) {
            Set<Id> deletedProductIds = new Set<Id>();
            for (QuoteLineItem qli : qlis) {
                if (qli.Product2Id != null) deletedProductIds.add(qli.Product2Id);
            }
            if (!deletedProductIds.isEmpty()) {
                List<Product2> bundleParents = [
                    SELECT Id FROM Product2
                    WHERE Id IN :deletedProductIds AND Type = 'Bundle' LIMIT 1
                ];
                if (!bundleParents.isEmpty()) return;
            }
        }

        Set<Id> quoteIds = new Set<Id>();
        for (QuoteLineItem qli : qlis) {
            if (qli.QuoteId != null) quoteIds.add(qli.QuoteId);
        }
        if (quoteIds.isEmpty()) return;

        Map<Id, Id> bundleParentQliToProductId = new Map<Id, Id>();
        Set<Id> bundleProductIds = new Set<Id>();
        for (QuoteLineItem bp : [
            SELECT Id, Product2Id FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds AND Product2.Type = 'Bundle'
        ]) {
            bundleParentQliToProductId.put(bp.Id, bp.Product2Id);
            bundleProductIds.add(bp.Product2Id);
        }
        if (bundleProductIds.isEmpty()) return;

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
        if (allGroupIds.isEmpty()) return;

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

        // ----------------------------------------------------------------
        // DELETE path: a deleted child line's QuoteLineRelationship is removed
        // as part of the delete, so we can't rely on it here. Preserve the
        // original product->group membership counting (unchanged behaviour).
        // ----------------------------------------------------------------
        if (isDelete) {
            // Count remaining distinct component lines per bundle instance (the
            // deleted lines are already gone by the after-delete pass).
            Map<Id, Map<Id, Set<Id>>> parentToGroupChildrenDel = new Map<Id, Map<Id, Set<Id>>>();
            for (Id pq : bundleParentQliToProductId.keySet()) {
                parentToGroupChildrenDel.put(pq, new Map<Id, Set<Id>>());
            }
            for (QuoteLineItem child : [
                SELECT Id, Product2Id FROM QuoteLineItem
                WHERE QuoteId IN :quoteIds
                  AND Product2Id != null
                  AND Product2.Type != 'Bundle'
            ]) {
                Set<Id> grpIds = childProductToGroups.get(child.Product2Id);
                if (grpIds == null) continue;
                for (Id pq : bundleParentQliToProductId.keySet()) {
                    List<ProductComponentGroup> bundleGroups = productToGroups.get(bundleParentQliToProductId.get(pq));
                    if (bundleGroups == null) continue;
                    for (ProductComponentGroup pcg : bundleGroups) {
                        if (grpIds.contains(pcg.Id)) {
                            if (!parentToGroupChildrenDel.get(pq).containsKey(pcg.Id)) {
                                parentToGroupChildrenDel.get(pq).put(pcg.Id, new Set<Id>());
                            }
                            parentToGroupChildrenDel.get(pq).get(pcg.Id).add(child.Id);
                        }
                    }
                }
            }

            Map<Id, String> delErrorMap = new Map<Id, String>();
            for (Id pq : bundleParentQliToProductId.keySet()) {
                List<ProductComponentGroup> groups = productToGroups.get(bundleParentQliToProductId.get(pq));
                if (groups == null) continue;
                Map<Id, Set<Id>> grpToChildren = parentToGroupChildrenDel.get(pq);
                for (ProductComponentGroup pcg : groups) {
                    Integer count = (grpToChildren != null && grpToChildren.containsKey(pcg.Id))
                                    ? grpToChildren.get(pcg.Id).size() : 0;
                    String msg;
                    if (pcg.MinBundleComponents != null && count < pcg.MinBundleComponents) {
                        msg = pcg.ParentProduct.Name + ', ' + pcg.Name +
                              ' has min value ' + pcg.MinBundleComponents +
                              ' and after deletion you will have ' + count +
                              '. Please keep the required components in ' + pcg.Name + '.';
                    } else if (pcg.MaxBundleComponents != null && count > pcg.MaxBundleComponents) {
                        msg = pcg.ParentProduct.Name + ', ' + pcg.Name +
                              ' has max value ' + pcg.MaxBundleComponents +
                              ' and after deletion you will have ' + count +
                              '. Please reconfigure the ' + pcg.Name + '.';
                    }
                    if (msg == null) continue;
                    delErrorMap.put(pq, msg);
                }
            }
            if (delErrorMap.isEmpty()) return;

            for (QuoteLineItem qli : qlis) {
                if (delErrorMap.containsKey(qli.Id)) { qli.addError(delErrorMap.get(qli.Id)); continue; }
                if (qli.Product2Id == null) continue;
                Set<Id> grpIds = childProductToGroups.get(qli.Product2Id);
                if (grpIds == null) continue;
                for (Id pq : bundleParentQliToProductId.keySet()) {
                    if (!delErrorMap.containsKey(pq)) continue;
                    List<ProductComponentGroup> bundleGroups = productToGroups.get(bundleParentQliToProductId.get(pq));
                    if (bundleGroups == null) continue;
                    Boolean matched = false;
                    for (ProductComponentGroup pcg : bundleGroups) {
                        if (grpIds.contains(pcg.Id)) { matched = true; break; }
                    }
                    if (matched) { qli.addError(delErrorMap.get(pq)); break; }
                }
            }
            return;
        }

        // ----------------------------------------------------------------
        // INSERT/UPDATE path: count members PER bundle instance. This is what
        // fixes the duplicate-bundle bug: each bundle's children are attributed
        // to that specific parent line, not pooled across every bundle of the
        // same product.
        //
        // Child -> parent is resolved from TWO sources, unioned:
        //   1. QuoteLineItem.ParentQuoteLineItemId  (structural; RLM sets it
        //      when the child line is created, so it is reliably present)
        //   2. QuoteLineRelationship                (fallback; RLM populates
        //      these across later requests, so on their own they can lag)
        // Using ParentQuoteLineItemId as the primary source means a bundle that
        // is missing a required component (e.g. Secondary Storage deselected)
        // is still detected on the update pass.
        //
        // The trigger invokes this on AFTER UPDATE (not after insert): the
        // recalc update runs once the bundle's lines are all present. We skip
        // any bundle parent that has no children yet (not-yet-configured) so a
        // partially-built bundle never produces a false min/max error.
        // ----------------------------------------------------------------
        List<QuoteLineItem> childLines = [
            SELECT Id, Product2Id, Quantity, ParentQuoteLineItemId
            FROM QuoteLineItem
            WHERE QuoteId IN :quoteIds
              AND Product2Id != null
              AND Product2.Type != 'Bundle'
        ];

        Map<Id, Id> childQliToParentQli = new Map<Id, Id>();
        for (QuoteLineItem child : childLines) {
            if (child.ParentQuoteLineItemId != null
                && bundleParentQliToProductId.containsKey(child.ParentQuoteLineItemId)) {
                childQliToParentQli.put(child.Id, child.ParentQuoteLineItemId);
            }
        }
        for (QuoteLineRelationship rel : [
            SELECT AssociatedQuoteLineId, MainQuoteLineId
            FROM QuoteLineRelationship
            WHERE MainQuoteLineId IN :bundleParentQliToProductId.keySet()
        ]) {
            if (rel.AssociatedQuoteLineId != null && rel.MainQuoteLineId != null
                && !childQliToParentQli.containsKey(rel.AssociatedQuoteLineId)) {
                childQliToParentQli.put(rel.AssociatedQuoteLineId, rel.MainQuoteLineId);
            }
        }

        // Per bundle instance: group -> set of distinct component LINES in it.
        // Min/Max count the number of selected components (lines), not their
        // quantities (e.g. the 480GB SSD at qty 2 is one line in the max-1
        // Primary Storage group; Secondary Storage min 2 is satisfied by two
        // distinct drive lines).
        Map<Id, Map<Id, Set<Id>>> parentToGroupChildren = new Map<Id, Map<Id, Set<Id>>>();
        Set<Id> configuredParents = new Set<Id>();   // parents that have >=1 child
        for (QuoteLineItem child : childLines) {
            Id pq = childQliToParentQli.get(child.Id);
            if (pq == null || !bundleParentQliToProductId.containsKey(pq)) continue;
            configuredParents.add(pq);
            Set<Id> grpIds = childProductToGroups.get(child.Product2Id);
            if (grpIds == null) continue;
            List<ProductComponentGroup> bundleGroups = productToGroups.get(bundleParentQliToProductId.get(pq));
            if (bundleGroups == null) continue;
            if (!parentToGroupChildren.containsKey(pq)) parentToGroupChildren.put(pq, new Map<Id, Set<Id>>());
            for (ProductComponentGroup pcg : bundleGroups) {
                if (grpIds.contains(pcg.Id)) {
                    if (!parentToGroupChildren.get(pq).containsKey(pcg.Id)) {
                        parentToGroupChildren.get(pq).put(pcg.Id, new Set<Id>());
                    }
                    parentToGroupChildren.get(pq).get(pcg.Id).add(child.Id);
                }
            }
        }

        Map<Id, String> errorMap = new Map<Id, String>();
        for (Id pq : bundleParentQliToProductId.keySet()) {
            // Skip bundles that aren't configured yet (no children) — a
            // partially-built bundle must not raise a false min/max error.
            if (!configuredParents.contains(pq)) continue;
            List<ProductComponentGroup> groups = productToGroups.get(bundleParentQliToProductId.get(pq));
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
                errorMap.put(pq, msg);
            }
        }
        if (errorMap.isEmpty()) return;

        for (QuoteLineItem qli : qlis) {
            if (errorMap.containsKey(qli.Id)) {
                qli.addError(errorMap.get(qli.Id));
                continue;
            }
            // Surface the error on a child line only if it belongs to the bundle
            // instance that actually breached its cardinality.
            Id pq = childQliToParentQli.get(qli.Id);
            if (pq != null && errorMap.containsKey(pq)) {
                qli.addError(errorMap.get(pq));
            }
        }
    }
}
