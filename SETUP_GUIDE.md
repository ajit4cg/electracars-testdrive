# Electra Cars – Test Drive Agent Setup Guide

## Prerequisites
- Salesforce org with **Automotive Cloud** enabled
- **Agentforce** license (Einstein for Service)
- **Digital Engagement** (for WhatsApp/SMS)
- Experience Cloud site created

---

## Step 1 – Deploy Metadata
```bash
sf project deploy start --source-dir force-app/main/default
```

---

## Step 2 – Automotive Cloud Setup
1. Enable Automotive Cloud in Setup > Automotive Cloud Settings
2. Confirm `Vehicle__c` object exists (standard AC object)
3. Create a Record Type `Dealership` on the Account object
4. Add sample dealership Accounts with BillingPostalCode populated

---

## Step 3 – Agentforce Agent Setup
1. Go to Setup > Agents > New Agent
2. Select the deployed `ElectraTestDriveAgent` metadata or recreate manually
3. Link Agent Actions to the `@InvocableMethod` in `TestDriveBookingController`
4. Activate the agent

---

## Step 4 – Embedded Service (Chat) Setup
1. Setup > Embedded Service Deployments > New Deployment
2. Name it `ElectraCars_TestDrive` (must match `embeddedServiceName` property)
3. Select your Experience Site as the deployment target
4. Link the Agentforce agent to this deployment
5. Copy the generated snippet — it loads automatically via `agentChatLauncher`

---

## Step 5 – WhatsApp / Digital Engagement
1. Setup > Messaging Settings > New Channel > WhatsApp
2. Connect your WhatsApp Business Account via Meta
3. Create a Messaging Channel record
4. The `TestDriveNotificationService` will use this channel for outbound messages

---

## Step 6 – Experience Site
1. Go to Digital Experiences > Builder > ElectraCars site
2. Add a new page: "Test Drive"
3. Drag `testDriveBooking` component onto the page
4. Drag `agentChatLauncher` component onto the page (renders as floating button)
5. Publish the site

---

## Step 7 – Data Cloud (Optional Enhancement)
1. Connect Data Cloud to your org
2. Create a Unified Individual profile mapping Lead + TestDrive__c
3. Build a segment: "Website visitors who viewed vehicle pages but haven't booked"
4. Use this segment to trigger proactive Agentforce nudges via Marketing Cloud

---

## Agentforce Conversation Flow
```
Customer: "I want to test drive the Apex"
Agent:    "Great choice! What date works for you?"
Customer: "Next Saturday"
Agent:    "Morning, Afternoon, or Evening?"
Customer: "Morning"
Agent:    "What's your zip code so I can find the nearest dealership?"
Customer: "90210"
Agent:    "Got it! And your name and email?"
Customer: "Alex, alex@email.com"
Agent:    "How would you like your confirmation — WhatsApp, SMS, or Email?"
Customer: "WhatsApp"
Agent:    "Perfect! Booking your Electra Apex test drive for Saturday morning
           at Electra Beverly Hills. Shall I confirm?"
Customer: "Yes"
Agent:    [Calls CreateTestDriveBooking action]
          "Done! Your booking is TD-0042. See you Saturday! 🚗"
```
