/**
 * Test coverage for FullCrmHello.
 */
@IsTest
private class FullCrmHelloTest {
    @IsTest
    static void greetingReturnsOrgName() {
        Test.startTest();
        String result = FullCrmHello.greeting();
        Test.stopTest();

        System.assert(
            result.startsWith('fullcrm connected to '),
            'greeting() should include the connection prefix'
        );
        System.assert(
            result.contains(UserInfo.getOrganizationName()),
            'greeting() should include the current org name'
        );
    }
}
