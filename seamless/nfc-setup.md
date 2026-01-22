# NFC Tags for Meal Prep

Tap container → Log meal. Zero friction, zero Claude dependency.

## Concept

1. Prep batch meal → Create in Nexus → Get meal ID
2. Write meal ID to NFC tag
3. Stick tag on container
4. Tap phone when eating → Logs serving automatically

## Hardware

- **NFC Tags**: NTAG215 stickers (~$0.30 each)
  - Amazon: "NTAG215 NFC stickers" (50 pack ~$15)
  - Waterproof versions for fridge containers

## Setup

### Step 1: Create Batch Meal (Once)

Via Claude Code or n8n:
```
"Made chicken stir fry: 800g chicken, 400g rice. 5 portions"
→ Creates meal ID: 42
```

### Step 2: Write NFC Tag

**iOS**: Use "NFC Tools" app
1. Write → Add record → URL
2. URL: `nexus://meal/42` (or `https://n8n.rfanw/webhook/nfc?meal=42`)

**Android**: Same with NFC Tools app

### Step 3: Stick on Container

Put tag on lid. Done.

### Step 4: Tap to Log

When eating:
1. Tap phone on container lid
2. iOS opens URL → Shortcut triggers
3. Logs serving, decrements portions remaining
4. Shows notification: "Logged stir fry (4 portions left)"

## iOS Shortcut for NFC

```
Name: NFC Meal Log
Trigger: URL scheme "nexus://meal/{id}"

Actions:
1. Get URL parameter: meal_id
2. Get Contents of URL:
   POST https://n8n.rfanw/webhook/nfc-meal
   Body: {"meal_id": [meal_id], "action": "log_serving"}
3. Show Notification: [response]
```

## n8n Webhook (No Claude)

```javascript
// Direct insert, no AI needed
const mealId = $input.first().json.body.meal_id;

// Get meal info
const meal = await query(`
  SELECT id, name, portions_remaining, calories_per_portion, protein_per_portion
  FROM nutrition.meals WHERE id = $1
`, [mealId]);

if (meal.portions_remaining <= 0) {
  return { error: "No portions left!" };
}

// Log the food
await query(`
  INSERT INTO nutrition.food_log (date, meal_time, meal_id, portion_number, calories, protein_g, source)
  SELECT CURRENT_DATE,
         CASE WHEN EXTRACT(HOUR FROM NOW()) < 10 THEN 'breakfast'
              WHEN EXTRACT(HOUR FROM NOW()) < 14 THEN 'lunch'
              WHEN EXTRACT(HOUR FROM NOW()) < 17 THEN 'snack'
              ELSE 'dinner' END,
         id, total_portions - portions_remaining + 1,
         calories_per_portion, protein_per_portion, 'nfc'
  FROM nutrition.meals WHERE id = $1
`, [mealId]);

// Decrement portions
await query(`
  UPDATE nutrition.meals SET portions_remaining = portions_remaining - 1 WHERE id = $1
`, [mealId]);

return {
  success: true,
  message: `${meal.name} logged (${meal.portions_remaining - 1} left)`
};
```

## Tag Placement Ideas

| Container | Tag Location |
|-----------|--------------|
| Glass meal prep | On lid (outside) |
| Plastic container | Side or lid |
| Freezer bag | Attached card with tag |
| Supplement bottle | Bottom or side |

## Meal Prep Workflow

1. **Sunday meal prep**:
   - Cook batch meals
   - Tell Claude: "Made X, Y, Z batches"
   - Claude creates meals, returns IDs

2. **Label containers**:
   - Write NFC tags with meal IDs
   - Or print QR codes (backup)

3. **During week**:
   - Grab container
   - Tap phone
   - Eat
   - Done

## Multi-Serving Containers

For family-size containers where you take partial:

Tag URL: `nexus://meal/42?prompt=true`

Shortcut asks: "How many servings?" → Logs that many

## Re-writable Tags

When batch is done:
1. Create new batch meal
2. Re-write same tag with new meal ID
3. Reuse container + tag

NTAG215 supports 100,000+ rewrites.
