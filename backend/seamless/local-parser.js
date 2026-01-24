/**
 * Local Parser for Nexus
 * Parses common inputs WITHOUT Claude - pattern matching + fuzzy search
 * Use as fallback when Claude is unavailable
 */

// ============================================================================
// PATTERN DEFINITIONS
// ============================================================================

const PATTERNS = {
  // Weight: "w 75.5", "weight 75.5", "75.5 kg", "75.5kg"
  weight: [
    /^w\s*(\d+\.?\d*)/i,
    /^weight\s*(\d+\.?\d*)/i,
    /^(\d+\.?\d*)\s*kg/i,
    /^(\d+\.?\d*)\s*lbs?/i,
  ],

  // Water: "water", "w8r", "250ml", "2 glasses", "drank water"
  water: [
    /^water$/i,
    /^w8r$/i,
    /^(\d+)\s*ml/i,
    /^(\d+)\s*glass(?:es)?/i,
    /^drank\s+water/i,
    /^log\s+water/i,
  ],

  // Mood: "m 7 6", "mood 7", "energy 5", "m7e6"
  mood: [
    /^m\s*(\d+)\s*(\d+)?/i,
    /^mood\s*(\d+)/i,
    /^energy\s*(\d+)/i,
    /^m(\d)e(\d)/i,
    /^feeling\s+(\d+)/i,
  ],

  // Habits: "done meditation", "did exercise", "✓ reading"
  habit: [
    /^done\s+(.+)/i,
    /^did\s+(.+)/i,
    /^completed?\s+(.+)/i,
    /^[✓✔☑]\s*(.+)/i,
    /^(\w+)\s+done$/i,
  ],

  // Supplements: "took vitamin", "creatine", "supps"
  supplement: [
    /^took\s+(.+)/i,
    /^(vitamin\s*\w*)/i,
    /^(creatine|omega|magnesium|zinc|d3|b12|iron|calcium)/i,
  ],

  // Quick foods: "coffee", "banana", common items
  quickFood: [
    /^(coffee|tea|espresso)(?:\s+with\s+milk)?/i,
    /^(banana|apple|orange)s?/i,
    /^(\d+)\s*(eggs?)/i,
    /^(protein\s*shake)/i,
    /^(oatmeal|oats)/i,
  ],

  // Batch meal reference: "stir fry serving 2", "meal 42", "leftover curry"
  batchMeal: [
    /^(.+?)\s*(?:serving|portion)\s*(\d+)?(?:\s*of\s*(\d+))?/i,
    /^meal\s*#?(\d+)/i,
    /^leftover\s+(.+)/i,
  ],

  // Shopping: "add X to list", "buy X", "need X"
  shopping: [
    /^add\s+(.+?)\s+to\s+(?:shopping\s+)?list/i,
    /^buy\s+(.+)/i,
    /^need\s+(.+)/i,
    /^shopping[:\s]+(.+)/i,
  ],

  // Queries: "today", "summary", "protein", "calories"
  query: [
    /^today(?:'s)?\s*(summary|stats|nutrition)?/i,
    /^(?:how\s+much\s+)?(protein|calories|carbs|fat)\s*(?:today)?/i,
    /^summary/i,
    /^stats/i,
  ],
};

// Common foods with approximate macros (per typical serving)
const QUICK_FOODS = {
  coffee: { calories: 5, protein: 0, carbs: 0, fat: 0, serving: "1 cup" },
  "coffee with milk": { calories: 30, protein: 1, carbs: 2, fat: 1, serving: "1 cup" },
  tea: { calories: 2, protein: 0, carbs: 0, fat: 0, serving: "1 cup" },
  espresso: { calories: 3, protein: 0, carbs: 0, fat: 0, serving: "1 shot" },
  banana: { calories: 105, protein: 1, carbs: 27, fat: 0, serving: "1 medium" },
  apple: { calories: 95, protein: 0, carbs: 25, fat: 0, serving: "1 medium" },
  orange: { calories: 62, protein: 1, carbs: 15, fat: 0, serving: "1 medium" },
  egg: { calories: 78, protein: 6, carbs: 1, fat: 5, serving: "1 large" },
  eggs: { calories: 156, protein: 12, carbs: 2, fat: 10, serving: "2 large" },
  "protein shake": { calories: 150, protein: 30, carbs: 5, fat: 2, serving: "1 scoop" },
  oatmeal: { calories: 150, protein: 5, carbs: 27, fat: 3, serving: "1 cup cooked" },
  oats: { calories: 150, protein: 5, carbs: 27, fat: 3, serving: "1/2 cup dry" },
};

// Habit name aliases
const HABIT_ALIASES = {
  meditation: ["meditate", "meditated", "mindfulness"],
  exercise: ["workout", "gym", "worked out", "exercised", "training"],
  reading: ["read", "book"],
  journal: ["journaling", "journaled", "wrote"],
  water: ["hydration", "drank water"],
  sleep: ["slept", "sleep by 11"],
  "no alcohol": ["no drinking", "sober", "dry"],
};

// ============================================================================
// PARSER FUNCTIONS
// ============================================================================

function parseInput(text) {
  const input = text.trim();

  // Try each pattern category
  for (const [type, patterns] of Object.entries(PATTERNS)) {
    for (const pattern of patterns) {
      const match = input.match(pattern);
      if (match) {
        return parseByType(type, match, input);
      }
    }
  }

  // No pattern matched - return unparsed for Claude fallback
  return { parsed: false, original: input };
}

function parseByType(type, match, original) {
  switch (type) {
    case "weight":
      return {
        parsed: true,
        type: "weight",
        data: {
          weight_kg: parseFloat(match[1]),
          unit: original.includes("lb") ? "lbs" : "kg",
        },
        sql: `INSERT INTO health.metrics (recorded_at, date, source, metric_type, value, unit)
              VALUES (NOW(), CURRENT_DATE, 'local', 'weight', ${parseFloat(match[1])}, 'kg')`,
      };

    case "water":
      let amount = 250; // default
      if (match[1]) {
        amount = original.includes("glass") ? parseInt(match[1]) * 250 : parseInt(match[1]);
      }
      return {
        parsed: true,
        type: "water",
        data: { amount_ml: amount },
        sql: `INSERT INTO nutrition.water_log (date, amount_ml, source)
              VALUES (CURRENT_DATE, ${amount}, 'local')`,
      };

    case "mood":
      const mood = parseInt(match[1]) || null;
      const energy = parseInt(match[2]) || null;
      return {
        parsed: true,
        type: "mood",
        data: { mood_score: mood, energy_score: energy },
        sql: `INSERT INTO core.daily_journal (date, mood_score, energy_score)
              VALUES (CURRENT_DATE, ${mood}, ${energy})
              ON CONFLICT (date) DO UPDATE SET
                mood_score = COALESCE(${mood}, core.daily_journal.mood_score),
                energy_score = COALESCE(${energy}, core.daily_journal.energy_score)`,
      };

    case "habit":
      const habitName = normalizeHabit(match[1]);
      return {
        parsed: true,
        type: "habit",
        data: { habit_name: habitName },
        sql: `INSERT INTO activity.habit_log (habit_id, date, completed)
              SELECT id, CURRENT_DATE, TRUE FROM activity.habits
              WHERE LOWER(name) LIKE LOWER('%${habitName}%') AND is_active = TRUE
              LIMIT 1
              ON CONFLICT (habit_id, date) DO UPDATE SET completed = TRUE`,
      };

    case "supplement":
      const suppName = match[1];
      return {
        parsed: true,
        type: "supplement",
        data: { name: suppName },
        sql: `INSERT INTO health.supplement_log (supplement_id, date)
              SELECT id, CURRENT_DATE FROM health.supplements
              WHERE LOWER(name) LIKE LOWER('%${suppName}%')
              LIMIT 1`,
      };

    case "quickFood":
      const food = match[0].toLowerCase();
      const quantity = parseInt(match[1]) || 1;
      const foodData = QUICK_FOODS[food] || QUICK_FOODS[match[2]?.toLowerCase()];

      if (foodData) {
        const multiplier = food.includes("egg") ? quantity : 1;
        return {
          parsed: true,
          type: "food",
          data: {
            description: original,
            calories: foodData.calories * multiplier,
            protein_g: foodData.protein * multiplier,
            carbs_g: foodData.carbs * multiplier,
            fat_g: foodData.fat * multiplier,
          },
          sql: `INSERT INTO nutrition.food_log
                (date, meal_time, description, calories, protein_g, carbs_g, fat_g, source, confidence)
                VALUES (CURRENT_DATE, '${inferMealTime()}', '${original}',
                        ${foodData.calories * multiplier}, ${foodData.protein * multiplier},
                        ${foodData.carbs * multiplier}, ${foodData.fat * multiplier},
                        'local', 'high')`,
        };
      }
      break;

    case "batchMeal":
      const mealName = match[1];
      const servingNum = parseInt(match[2]) || 1;
      return {
        parsed: true,
        type: "batch_meal",
        data: { meal_name: mealName, serving: servingNum },
        // This requires a lookup, return partial
        needsLookup: true,
        lookupSql: `SELECT id, name, calories_per_portion, protein_per_portion
                    FROM nutrition.meals
                    WHERE LOWER(name) LIKE LOWER('%${mealName}%')
                    AND portions_remaining > 0
                    ORDER BY prep_date DESC LIMIT 1`,
      };

    case "shopping":
      const items = match[1].split(/,|and/).map(s => s.trim()).filter(Boolean);
      return {
        parsed: true,
        type: "shopping",
        data: { items },
        sql: items.map(item =>
          `INSERT INTO nutrition.shopping_list_items (list_id, item_name, source)
           SELECT id, '${item}', 'local' FROM nutrition.shopping_lists
           WHERE status = 'active' ORDER BY created_at DESC LIMIT 1`
        ).join("; "),
      };

    case "query":
      return {
        parsed: true,
        type: "query",
        data: { query_type: match[1] || "summary" },
        sql: `SELECT * FROM core.daily_summary WHERE date = CURRENT_DATE`,
      };
  }

  return { parsed: false, original };
}

function normalizeHabit(input) {
  const lower = input.toLowerCase().trim();

  for (const [habit, aliases] of Object.entries(HABIT_ALIASES)) {
    if (habit.includes(lower) || aliases.some(a => a.includes(lower) || lower.includes(a))) {
      return habit;
    }
  }

  return lower;
}

function inferMealTime() {
  const hour = new Date().getHours();
  if (hour < 10) return "breakfast";
  if (hour < 14) return "lunch";
  if (hour < 17) return "snack";
  return "dinner";
}

// ============================================================================
// EXPORTS
// ============================================================================

export { parseInput, QUICK_FOODS, HABIT_ALIASES };

// For direct testing
if (process.argv[1]?.includes("local-parser")) {
  const testInputs = [
    "w 75.5",
    "weight 76",
    "water",
    "2 glasses",
    "500ml",
    "m 7 6",
    "mood 8",
    "done meditation",
    "did exercise",
    "coffee",
    "2 eggs",
    "banana",
    "protein shake",
    "stir fry serving 2",
    "add milk to list",
    "buy eggs and bread",
    "today",
    "took creatine",
    "vitamin d",
  ];

  console.log("Local Parser Test Results:\n");
  for (const input of testInputs) {
    const result = parseInput(input);
    console.log(`"${input}"`);
    console.log(`  → ${result.parsed ? result.type : "NOT PARSED"}`);
    if (result.data) console.log(`  → ${JSON.stringify(result.data)}`);
    console.log();
  }
}
