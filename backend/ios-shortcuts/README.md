# iOS Shortcuts for Nexus

Quick-capture shortcuts for logging to Nexus without opening any app.

## Webhook Endpoints

These shortcuts call n8n webhooks which process through Claude and write to Nexus.

| Shortcut | Webhook | Trigger |
|----------|---------|---------|
| Log Food | `POST /webhook/nexus-food` | "Hey Siri, log food" |
| Log Water | `POST /webhook/nexus-water` | "Hey Siri, log water" |
| Log Weight | `POST /webhook/nexus-weight` | "Hey Siri, log weight" |
| Log Mood | `POST /webhook/nexus-mood` | "Hey Siri, log mood" |
| Quick Note | `POST /webhook/nexus-note` | "Hey Siri, nexus note" |

## Shortcut Configurations

### 1. Log Food (Voice → Claude → Nexus)

```
Name: Log Food
Trigger: "Hey Siri, log food" or widget tap

Actions:
1. Dictate Text (or Ask for Input)
   - Prompt: "What did you eat?"
   - Store in: FoodInput

2. Get Contents of URL
   - URL: https://n8n.rfanw/webhook/nexus-food
   - Method: POST
   - Headers: Content-Type: application/json
   - Body: {"text": "[FoodInput]", "source": "siri"}

3. Get Dictionary Value (success)
4. If success = true:
     Show Notification: "Logged: [calories] cal, [protein]g protein"
   Else:
     Show Notification: "Failed to log"
```

### 2. Log Water (One-tap)

```
Name: Log Water
Trigger: Widget tap or "Hey Siri, log water"

Actions:
1. Choose from Menu:
   - "1 glass (250ml)"
   - "2 glasses (500ml)"
   - "Custom..."

2. If Custom: Ask for Input (number)

3. Get Contents of URL
   - URL: https://n8n.rfanw/webhook/nexus-water
   - Method: POST
   - Body: {"amount_ml": [SelectedAmount]}

4. Show Notification: "Water logged. Today: [total]ml"
```

### 3. Log Weight (Morning routine)

```
Name: Log Weight
Trigger: "Hey Siri, log weight" or automation at 7am

Actions:
1. Ask for Input
   - Prompt: "Weight in kg?"
   - Input Type: Number

2. Get Contents of URL
   - URL: https://n8n.rfanw/webhook/nexus-weight
   - Method: POST
   - Body: {"weight_kg": [Input]}

3. Show Notification: "Weight logged: [Input] kg"
```

### 4. Log Mood (Evening check-in)

```
Name: Log Mood
Trigger: Automation at 9pm or "Hey Siri, log mood"

Actions:
1. Choose from Menu: Rate your mood (1-10)
   Options: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
   Store in: Mood

2. Choose from Menu: Rate your energy (1-10)
   Store in: Energy

3. Ask for Input (optional):
   Prompt: "Any notes? (or skip)"
   Store in: Notes

4. Get Contents of URL
   - URL: https://n8n.rfanw/webhook/nexus-mood
   - Body: {"mood": [Mood], "energy": [Energy], "notes": "[Notes]"}

5. Show Notification: "Mood logged"
```

### 5. Quick Log (Universal, Claude interprets)

```
Name: Nexus
Trigger: "Hey Siri, Nexus" or share sheet

Actions:
1. If Shortcut Input exists:
     Set Variable: Input = Shortcut Input
   Else:
     Dictate Text → Store in: Input

2. Get Contents of URL
   - URL: https://n8n.rfanw/webhook/nexus-universal
   - Method: POST
   - Body: {"text": "[Input]", "source": "siri", "context": "auto"}

3. Get Dictionary Value: response
4. Show Notification: [response]
```

## n8n Webhook Handler (Universal)

The universal webhook uses Claude to interpret what the user wants:

```javascript
// In n8n Code node after webhook
const input = $input.first().json;

const prompt = `
User said: "${input.text}"

Determine what they want to log and extract the data:
- Food: extract description, estimate calories/protein
- Water: extract amount
- Weight: extract weight_kg
- Mood: extract mood/energy scores
- Habit: which habit to mark complete
- Note: save as general note

Return JSON: {type, data}
`;

// Send to Claude API, get structured response
// Route to appropriate Nexus insert
```

## Widget Setup

1. **Add Shortcuts widget** to Home Screen
2. **Pin these shortcuts**:
   - Log Food (most used)
   - Log Water
   - Quick Nexus

3. **Stack widget** for minimal space:
   - Small widget showing "Log Food"
   - Swipe for Water, Mood, etc.

## Automations

| Time | Automation |
|------|------------|
| 7:00 AM | Prompt for weight |
| 7:30 AM | Show Whoop recovery (from HA) |
| 12:00 PM | Reminder to log lunch |
| 9:00 PM | Prompt for mood/energy |
| 10:00 PM | Show daily summary |

## Apple Watch

These shortcuts work on Apple Watch:
- Voice: "Hey Siri, log food"
- Complication: Tap to open shortcut

Recommended watch complications:
- Log Food (most used)
- Log Water (quick tap)

## Share Sheet Integration

Add "Quick Log" to share sheet to:
- Share a recipe → Claude extracts ingredients → Creates meal template
- Share restaurant menu → Log what you ate
- Share photo of food → (future: Claude vision estimates)
