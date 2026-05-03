List<ApexClass> classes = [SELECT Id, Name, Body FROM ApexClass WHERE Name = 'BookTestDriveAction' LIMIT 1];
if (!classes.isEmpty()) {
    System.debug('CLASSSTART' + classes[0].Body + 'CLASSEND');
}
