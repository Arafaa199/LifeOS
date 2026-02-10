# Photo Food Logging Setup Guide

This guide walks you through setting up the photo-based food logging feature with Claude Vision in n8n.

## ✅ What This Does

- **Upload a photo** of your food
- **Claude Vision identifies** what food is in the image
- **Estimates nutrition** (calories, protein, carbs, fat)
- **Saves to database** automatically
- **Returns structured data** to your iOS app

---

## 🚀 Quick Setup (5 minutes)

### Step 1: Get Anthropic API Key

1. Go to https://console.anthropic.com
2. Sign in or create account
3. Go to API Keys → Create Key
4. Copy your API key (starts with `sk-ant-...`)

---

### Step 2: Add Credential to n8n

1. **Open n8n:** https://n8n.rfanw
2. **Go to:** Credentials (left sidebar)
3. **Click:** Add Credential
4. **Search:** "Anthropic"
5. **Select:** Anthropic API
6. **Fill in:**
   - Name: `Anthropic API` (exactly this)
   - API Key: `sk-ant-...` (paste your key)
7. **Save**

---

### Step 3: Import Workflow

1. **Go to:** Workflows (left sidebar)
2. **Click:** Import from File
3. **Select:** The photo-food-webhook.json file from your n8n-workflows directory
4. **Click:** Import

**Workflow will appear as:** "Nexus Photo Food Logger"

---

### Step 4: Configure Credentials

The workflow should auto-detect your "Anthropic API" credential, but verify:

1. **Open workflow:** Click "Nexus Photo Food Logger"
2. **Find node:** "Claude Vision Analysis" (second node)
3. **Check credential:** Should show "Anthropic API" credential
4. **If missing:**
   - Click the node
   - Select "Credentials" → Choose "Anthropic API"
   - Save

---

### Step 5: Activate Workflow

1. **Top right:** Toggle switch to "Active"
2. **Status:** Should show green "Active"

**Your endpoint is now live:**
```
https://n8n.rfanw/webhook/nexus-photo-food
```

---

## 🧪 Test the Endpoint

### Test 1: Using curl (Terminal)

```bash
# Create a test image or use an existing one
curl -X POST https://n8n.rfanw/webhook/nexus-photo-food \
  -F "photo=@/path/to/food-photo.jpg" \
  -F "source=curl-test" \
  -F "context=lunch"
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Food logged from photo: Grilled chicken with vegetables",
  "data": {
    "id": 123,
    "food_items": ["chicken breast", "broccoli", "carrots"],
    "calories": 350,
    "protein": 42,
    "carbs": 18,
    "fat": 10,
    "confidence": "high",
    "notes": "Well-cooked protein with steamed vegetables"
  }
}
```

---

### Test 2: Using iOS App

1. **Open Nexus app** on iPhone
2. **Go to:** Food tab
3. **Tap:** "Camera" button
4. **Grant:** Camera permission
5. **Take photo** of food
6. **Tap:** "Use Photo"
7. **Tap:** "Log Photo"
8. **Wait:** 3-10 seconds for processing

**Expected:**
- ✅ Shows "Processing..."
- ✅ Success alert with identified food
- ✅ Dashboard updates with calories/protein
- ✅ Recent logs shows photo entry

---

## 🐛 Troubleshooting

### Issue: "Failed to process photo"

**Check Console in n8n:**
1. Go to workflow
2. Click "Executions" tab
3. Find failed execution
4. Check error message

**Common causes:**
- ❌ Anthropic API key invalid → Re-enter credential
- ❌ API quota exceeded → Check Anthropic dashboard
- ❌ Photo too large → App resizes to 1024px, should be OK
- ❌ Database connection failed → Check PostgreSQL credential

---

### Issue: "No JSON found in response"

This means Claude didn't return valid JSON. Check:

1. **Claude's response:**
   - Go to failed execution
   - Look at "Claude Vision Analysis" node output
   - See what Claude actually returned

2. **Fix:**
   - Usually happens with very unclear photos
   - Workflow has fallback: Creates entry with 0 nutrition
   - User should re-log manually

---

### Issue: Photo uploads but no response

**Check n8n logs:**
```bash
ssh pivpn "docker logs n8n 2>&1 | tail -50"
```

Look for:
- Webhook received
- Claude API call
- Database insert
- Response sent

---

## 📊 How It Works

```
iOS App
  │
  ├─► Take photo
  │
  ├─► Compress to <500KB
  │
  ├─► Upload to n8n
  │
n8n Webhook
  │
  ├─► Receive multipart/form-data
  │
  ├─► Extract photo + context
  │
  ├─► Send to Claude Vision API
  │
Claude Vision
  │
  ├─► Analyze image
  │
  ├─► Identify food items
  │
  ├─► Estimate nutrition
  │
  ├─► Return JSON
  │
n8n Parser
  │
  ├─► Parse JSON response
  │
  ├─► Extract nutrition data
  │
PostgreSQL
  │
  ├─► INSERT into nutrition.food_log
  │
  ├─► Save metadata (food_items, confidence, etc)
  │
Response
  │
  └─► Return to iOS app with nutrition data
```

---

## 💰 Cost Estimate

**Anthropic Claude Vision Pricing:**
- **Model:** Claude 3.5 Sonnet
- **Input:** ~1,500 tokens per image (with prompt)
- **Output:** ~200 tokens (JSON response)
- **Cost per request:** ~$0.005 USD (half a cent)

**Monthly estimate (100 photos):**
- 100 photos × $0.005 = **$0.50/month**

Very affordable for personal use!

---

## 🔒 Security Notes

**API Key:**
- Keep your Anthropic API key secure
- Don't commit it to git
- Store only in n8n credentials

**Photo Data:**
- Photos are sent to Anthropic's API
- Not stored permanently on server
- Deleted after processing
- Nutrition data saved to database

**Privacy:**
- Claude Vision sees the photos you upload
- Follows Anthropic's privacy policy
- Data not used for training (as of Jan 2026)

---

## 📈 Improving Accuracy

**Tips for better results:**

1. **Good lighting** - Take photos in bright light
2. **Close-up** - Get close to the food
3. **Clear view** - Show the food clearly
4. **Add context** - Use the context field:
   - "leftover pizza from yesterday"
   - "homemade chicken curry"
   - "restaurant burger and fries"

**Context helps Claude:**
- Understand portion sizes
- Identify specific dishes
- Estimate more accurately

---

## ✅ Success Checklist

- [ ] Anthropic API key obtained
- [ ] Credential created in n8n
- [ ] Workflow imported
- [ ] Credential connected to node
- [ ] Workflow activated
- [ ] Tested with curl
- [ ] Tested from iOS app
- [ ] Database entries created
- [ ] iOS app shows results

**If all checked: Photo logging is working! 🎉**

---

## 🔧 Advanced Configuration

### Adjust Claude's Prompt

Edit the "Claude Vision Analysis" node:

```javascript
// Current prompt structure:
"I'm sending you a photo of food. Please identify..."

// You can modify to:
// - Request more detail
// - Focus on specific nutrients
// - Add dietary preferences
// - Request ingredient lists
```

### Change Temperature

Lower temperature = more consistent responses
Higher temperature = more creative interpretations

Default: 0.3 (good for structured output)

### Increase Max Tokens

If responses are cut off:
- Default: 500 tokens
- Increase to: 1000 tokens

---

## 📞 Support

**Issues?**
1. Check n8n execution logs
2. Verify Anthropic API key works
3. Test endpoint with curl
4. Check iOS app Console logs
5. Verify database connection

**Still stuck?**
- Check n8n community forums
- Anthropic API status page
- iOS app TESTING_GUIDE.md

---

*Last Updated: 2026-01-19*
*Ready to use with Nexus iOS app*
