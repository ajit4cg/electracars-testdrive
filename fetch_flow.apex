List<FlowDefinitionView> defs = [
    SELECT Id, ApiName, ActiveVersionId, Label
    FROM FlowDefinitionView
    WHERE ApiName = 'Send_Confirmation_SMS_Mail'
    LIMIT 1
];
System.debug('Flow def: ' + JSON.serialize(defs));
