#!/usr/bin/env node

/**
 * Nexus MCP Server
 * Provides Claude with direct access to your personal life database
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import pg from "pg";

const { Pool } = pg;

// Database connection
const pool = new Pool({
  host: process.env.NEXUS_HOST || "localhost",
  port: parseInt(process.env.NEXUS_PORT || "5432"),
  database: process.env.NEXUS_DB || "nexus",
  user: process.env.NEXUS_USER || "nexus",
  password: process.env.NEXUS_PASSWORD,
});

// Helper to run queries
async function query(sql, params = []) {
  const client = await pool.connect();
  try {
    const result = await client.query(sql, params);
    return result.rows;
  } finally {
    client.release();
  }
}

// Create MCP server
const server = new Server(
  {
    name: "nexus",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
      resources: {},
    },
  }
);

// =============================================================================
// TOOLS - Actions Claude can take
// =============================================================================

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      // ─────────────────────────────────────────────────────────────────────
      // FOOD LOGGING
      // ─────────────────────────────────────────────────────────────────────
      {
        name: "log_food",
        description: `Log food consumption. Accepts natural language descriptions.
Examples:
- "2 eggs and toast for breakfast"
- "chicken stir fry batch, serving 2 of 5"
- "coffee with milk, ~50 calories"
- "ate out - burger and fries, estimate 900 cal"`,
        inputSchema: {
          type: "object",
          properties: {
            description: {
              type: "string",
              description: "What was eaten (natural language)",
            },
            meal_time: {
              type: "string",
              enum: ["breakfast", "lunch", "dinner", "snack"],
              description: "Meal time (optional, will be inferred from time of day)",
            },
            calories: {
              type: "number",
              description: "Calories (optional, estimate if not provided)",
            },
            protein_g: { type: "number", description: "Protein in grams" },
            carbs_g: { type: "number", description: "Carbs in grams" },
            fat_g: { type: "number", description: "Fat in grams" },
            confidence: {
              type: "string",
              enum: ["high", "medium", "low"],
              description: "Confidence in the nutritional values",
            },
          },
          required: ["description"],
        },
      },
      {
        name: "log_batch_meal",
        description: `Create a batch meal for meal prep tracking.
Example: "Made chicken stir fry: 800g chicken, 400g rice, 300g broccoli. Makes 5 portions"`,
        inputSchema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Meal name" },
            ingredients: {
              type: "string",
              description: "Ingredients with quantities (natural language)",
            },
            portions: { type: "number", description: "Number of portions" },
            calories_per_portion: { type: "number" },
            protein_per_portion: { type: "number" },
            carbs_per_portion: { type: "number" },
            fat_per_portion: { type: "number" },
          },
          required: ["name", "portions"],
        },
      },
      {
        name: "log_water",
        description: "Log water intake",
        inputSchema: {
          type: "object",
          properties: {
            amount_ml: { type: "number", description: "Amount in ml (default 250)" },
            glasses: { type: "number", description: "Or specify number of glasses (250ml each)" },
          },
        },
      },

      // ─────────────────────────────────────────────────────────────────────
      // HEALTH METRICS
      // ─────────────────────────────────────────────────────────────────────
      {
        name: "log_weight",
        description: "Log body weight",
        inputSchema: {
          type: "object",
          properties: {
            weight_kg: { type: "number", description: "Weight in kg" },
            body_fat_pct: { type: "number", description: "Body fat percentage (optional)" },
          },
          required: ["weight_kg"],
        },
      },
      {
        name: "log_metric",
        description: "Log any health metric (HRV, blood pressure, etc.)",
        inputSchema: {
          type: "object",
          properties: {
            metric_type: {
              type: "string",
              description: "Type of metric (hrv, blood_pressure, rhr, etc.)",
            },
            value: { type: "number", description: "The value" },
            unit: { type: "string", description: "Unit of measurement" },
            source: { type: "string", description: "Source (manual, device name, etc.)" },
          },
          required: ["metric_type", "value"],
        },
      },
      {
        name: "log_supplement",
        description: "Log taking a supplement or medication",
        inputSchema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Supplement name" },
            dose: { type: "string", description: "Dose taken (optional)" },
          },
          required: ["name"],
        },
      },

      // ─────────────────────────────────────────────────────────────────────
      // MOOD & JOURNAL
      // ─────────────────────────────────────────────────────────────────────
      {
        name: "log_mood",
        description: "Log daily mood, energy, and stress levels (1-10 scale)",
        inputSchema: {
          type: "object",
          properties: {
            mood: { type: "number", minimum: 1, maximum: 10 },
            energy: { type: "number", minimum: 1, maximum: 10 },
            stress: { type: "number", minimum: 1, maximum: 10 },
            notes: { type: "string", description: "Any notes about the day" },
            gratitude: {
              type: "array",
              items: { type: "string" },
              description: "Things you're grateful for",
            },
          },
        },
      },
      {
        name: "log_habit",
        description: "Mark a habit as completed for today",
        inputSchema: {
          type: "object",
          properties: {
            habit_name: { type: "string", description: "Name of the habit" },
            completed: { type: "boolean", default: true },
            notes: { type: "string" },
          },
          required: ["habit_name"],
        },
      },

      // ─────────────────────────────────────────────────────────────────────
      // SHOPPING & PANTRY
      // ─────────────────────────────────────────────────────────────────────
      {
        name: "add_to_shopping_list",
        description: "Add items to the shopping list",
        inputSchema: {
          type: "object",
          properties: {
            items: {
              type: "array",
              items: { type: "string" },
              description: "Items to add",
            },
          },
          required: ["items"],
        },
      },
      {
        name: "update_pantry",
        description: "Update pantry inventory (add, remove, or update items)",
        inputSchema: {
          type: "object",
          properties: {
            action: { type: "string", enum: ["add", "remove", "update", "use"] },
            item_name: { type: "string" },
            quantity: { type: "number" },
            unit: { type: "string" },
            expiry_date: { type: "string", description: "YYYY-MM-DD format" },
          },
          required: ["action", "item_name"],
        },
      },

      // ─────────────────────────────────────────────────────────────────────
      // QUERIES
      // ─────────────────────────────────────────────────────────────────────
      {
        name: "get_today_summary",
        description: "Get today's summary (nutrition, health, spending)",
        inputSchema: { type: "object", properties: {} },
      },
      {
        name: "get_nutrition_today",
        description: "Get detailed nutrition log for today",
        inputSchema: { type: "object", properties: {} },
      },
      {
        name: "get_weekly_trends",
        description: "Get health and nutrition trends for the past week",
        inputSchema: { type: "object", properties: {} },
      },
      {
        name: "get_active_meals",
        description: "Get batch meals with remaining portions",
        inputSchema: { type: "object", properties: {} },
      },
      {
        name: "get_shopping_list",
        description: "Get current shopping list",
        inputSchema: { type: "object", properties: {} },
      },
      {
        name: "get_low_stock",
        description: "Get pantry items that are low or expiring soon",
        inputSchema: { type: "object", properties: {} },
      },
      {
        name: "get_habits_today",
        description: "Get habit status for today",
        inputSchema: { type: "object", properties: {} },
      },
      {
        name: "search_food_history",
        description: "Search past food logs",
        inputSchema: {
          type: "object",
          properties: {
            query: { type: "string", description: "Search term" },
            days: { type: "number", description: "How many days back to search", default: 30 },
          },
          required: ["query"],
        },
      },
      {
        name: "query_nexus",
        description: "Run a custom SQL query on the Nexus database (read-only)",
        inputSchema: {
          type: "object",
          properties: {
            sql: { type: "string", description: "SQL query (SELECT only)" },
          },
          required: ["sql"],
        },
      },
    ],
  };
});

// =============================================================================
// TOOL HANDLERS
// =============================================================================

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      // ─────────────────────────────────────────────────────────────────────
      // FOOD LOGGING
      // ─────────────────────────────────────────────────────────────────────
      case "log_food": {
        const mealTime = args.meal_time || inferMealTime();
        const result = await query(
          `INSERT INTO nutrition.food_log
           (date, meal_time, description, calories, protein_g, carbs_g, fat_g,
            confidence, source)
           VALUES (CURRENT_DATE, $1, $2, $3, $4, $5, $6, $7, 'mcp')
           RETURNING id, date, meal_time, calories, protein_g`,
          [
            mealTime,
            args.description,
            args.calories || null,
            args.protein_g || null,
            args.carbs_g || null,
            args.fat_g || null,
            args.confidence || "medium",
          ]
        );

        // Get daily totals
        const totals = await query(
          `SELECT COALESCE(SUM(calories), 0) as calories,
                  COALESCE(SUM(protein_g), 0) as protein,
                  COUNT(*) as meals
           FROM nutrition.food_log WHERE date = CURRENT_DATE`
        );

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: true,
                logged: result[0],
                daily_totals: totals[0],
              }),
            },
          ],
        };
      }

      case "log_batch_meal": {
        const result = await query(
          `INSERT INTO nutrition.meals
           (name, total_portions, portions_remaining,
            calories_per_portion, protein_per_portion, carbs_per_portion, fat_per_portion,
            prep_date, is_template)
           VALUES ($1, $2, $2, $3, $4, $5, $6, CURRENT_DATE, FALSE)
           RETURNING id, name, total_portions, calories_per_portion`,
          [
            args.name,
            args.portions,
            args.calories_per_portion || null,
            args.protein_per_portion || null,
            args.carbs_per_portion || null,
            args.fat_per_portion || null,
          ]
        );
        return {
          content: [{ type: "text", text: JSON.stringify({ success: true, meal: result[0] }) }],
        };
      }

      case "log_water": {
        const amount = args.amount_ml || (args.glasses || 1) * 250;
        await query(
          `INSERT INTO nutrition.water_log (date, amount_ml, source)
           VALUES (CURRENT_DATE, $1, 'mcp')`,
          [amount]
        );
        const total = await query(
          `SELECT COALESCE(SUM(amount_ml), 0) as total
           FROM nutrition.water_log WHERE date = CURRENT_DATE`
        );
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: true,
                logged_ml: amount,
                daily_total_ml: total[0].total,
              }),
            },
          ],
        };
      }

      // ─────────────────────────────────────────────────────────────────────
      // HEALTH METRICS
      // ─────────────────────────────────────────────────────────────────────
      case "log_weight": {
        await query(
          `INSERT INTO health.metrics (recorded_at, date, source, metric_type, value, unit)
           VALUES (NOW(), CURRENT_DATE, 'mcp', 'weight', $1, 'kg')
           ON CONFLICT (recorded_at, source, metric_type) DO UPDATE SET value = $1`,
          [args.weight_kg]
        );
        if (args.body_fat_pct) {
          await query(
            `INSERT INTO health.metrics (recorded_at, date, source, metric_type, value, unit)
             VALUES (NOW(), CURRENT_DATE, 'mcp', 'body_fat', $1, '%')`,
            [args.body_fat_pct]
          );
        }
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: true,
                weight_kg: args.weight_kg,
                body_fat_pct: args.body_fat_pct,
              }),
            },
          ],
        };
      }

      case "log_metric": {
        await query(
          `INSERT INTO health.metrics (recorded_at, date, source, metric_type, value, unit)
           VALUES (NOW(), CURRENT_DATE, $1, $2, $3, $4)`,
          [args.source || "mcp", args.metric_type, args.value, args.unit || null]
        );
        return {
          content: [{ type: "text", text: JSON.stringify({ success: true, ...args }) }],
        };
      }

      case "log_supplement": {
        // Find or create supplement
        let supplement = await query(
          `SELECT id FROM health.supplements WHERE LOWER(name) LIKE LOWER($1) LIMIT 1`,
          [`%${args.name}%`]
        );

        if (supplement.length === 0) {
          supplement = await query(
            `INSERT INTO health.supplements (name, is_active) VALUES ($1, TRUE) RETURNING id`,
            [args.name]
          );
        }

        await query(
          `INSERT INTO health.supplement_log (supplement_id, date, notes)
           VALUES ($1, CURRENT_DATE, $2)`,
          [supplement[0].id, args.dose || null]
        );

        return {
          content: [{ type: "text", text: JSON.stringify({ success: true, supplement: args.name }) }],
        };
      }

      // ─────────────────────────────────────────────────────────────────────
      // MOOD & JOURNAL
      // ─────────────────────────────────────────────────────────────────────
      case "log_mood": {
        await query(
          `INSERT INTO core.daily_journal (date, mood_score, energy_score, stress_score, evening_note, gratitude)
           VALUES (CURRENT_DATE, $1, $2, $3, $4, $5)
           ON CONFLICT (date) DO UPDATE SET
             mood_score = COALESCE($1, core.daily_journal.mood_score),
             energy_score = COALESCE($2, core.daily_journal.energy_score),
             stress_score = COALESCE($3, core.daily_journal.stress_score),
             evening_note = COALESCE($4, core.daily_journal.evening_note),
             gratitude = COALESCE($5, core.daily_journal.gratitude),
             updated_at = NOW()`,
          [
            args.mood || null,
            args.energy || null,
            args.stress || null,
            args.notes || null,
            args.gratitude || null,
          ]
        );
        return { content: [{ type: "text", text: JSON.stringify({ success: true, ...args }) }] };
      }

      case "log_habit": {
        const habit = await query(
          `SELECT id FROM activity.habits WHERE LOWER(name) LIKE LOWER($1) AND is_active = TRUE LIMIT 1`,
          [`%${args.habit_name}%`]
        );

        if (habit.length === 0) {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  success: false,
                  error: `Habit "${args.habit_name}" not found`,
                }),
              },
            ],
          };
        }

        await query(
          `INSERT INTO activity.habit_log (habit_id, date, completed, notes)
           VALUES ($1, CURRENT_DATE, $2, $3)
           ON CONFLICT (habit_id, date) DO UPDATE SET completed = $2, notes = $3`,
          [habit[0].id, args.completed !== false, args.notes || null]
        );

        return {
          content: [
            { type: "text", text: JSON.stringify({ success: true, habit: args.habit_name }) },
          ],
        };
      }

      // ─────────────────────────────────────────────────────────────────────
      // SHOPPING & PANTRY
      // ─────────────────────────────────────────────────────────────────────
      case "add_to_shopping_list": {
        // Get or create active list
        let list = await query(
          `SELECT id FROM nutrition.shopping_lists WHERE status = 'active' ORDER BY created_at DESC LIMIT 1`
        );

        if (list.length === 0) {
          list = await query(
            `INSERT INTO nutrition.shopping_lists (name, status) VALUES ('Shopping List', 'active') RETURNING id`
          );
        }

        for (const item of args.items) {
          await query(
            `INSERT INTO nutrition.shopping_list_items (list_id, item_name, source)
             VALUES ($1, $2, 'mcp')`,
            [list[0].id, item]
          );
        }

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ success: true, added: args.items.length, items: args.items }),
            },
          ],
        };
      }

      case "update_pantry": {
        if (args.action === "add") {
          await query(
            `INSERT INTO nutrition.pantry (item_name, quantity, unit, expiry_date, storage_location)
             VALUES ($1, $2, $3, $4, $5)`,
            [
              args.item_name,
              args.quantity || 1,
              args.unit || "unit",
              args.expiry_date || null,
              args.location || "pantry",
            ]
          );
        } else if (args.action === "use" || args.action === "remove") {
          await query(
            `UPDATE nutrition.pantry SET quantity = quantity - $1, updated_at = NOW()
             WHERE LOWER(item_name) LIKE LOWER($2)`,
            [args.quantity || 1, `%${args.item_name}%`]
          );
        }
        return { content: [{ type: "text", text: JSON.stringify({ success: true, ...args }) }] };
      }

      // ─────────────────────────────────────────────────────────────────────
      // QUERIES
      // ─────────────────────────────────────────────────────────────────────
      case "get_today_summary": {
        const summary = await query(
          `SELECT * FROM core.daily_summary WHERE date = CURRENT_DATE`
        );
        const nutrition = await query(
          `SELECT COALESCE(SUM(calories), 0) as calories,
                  COALESCE(SUM(protein_g), 0) as protein,
                  COUNT(*) as meals
           FROM nutrition.food_log WHERE date = CURRENT_DATE`
        );
        const water = await query(
          `SELECT COALESCE(SUM(amount_ml), 0) as total
           FROM nutrition.water_log WHERE date = CURRENT_DATE`
        );

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                date: new Date().toISOString().split("T")[0],
                summary: summary[0] || {},
                nutrition: nutrition[0],
                water_ml: water[0].total,
              }),
            },
          ],
        };
      }

      case "get_nutrition_today": {
        const logs = await query(
          `SELECT id, meal_time, description, calories, protein_g, carbs_g, fat_g, confidence
           FROM nutrition.food_log
           WHERE date = CURRENT_DATE
           ORDER BY logged_at`
        );
        const totals = await query(
          `SELECT COALESCE(SUM(calories), 0) as calories,
                  COALESCE(SUM(protein_g), 0) as protein,
                  COALESCE(SUM(carbs_g), 0) as carbs,
                  COALESCE(SUM(fat_g), 0) as fat
           FROM nutrition.food_log WHERE date = CURRENT_DATE`
        );
        return {
          content: [{ type: "text", text: JSON.stringify({ logs, totals: totals[0] }) }],
        };
      }

      case "get_weekly_trends": {
        const trends = await query(
          `SELECT date, weight_kg, recovery_score, calories_consumed, protein_g, sleep_hours
           FROM core.daily_summary
           WHERE date >= CURRENT_DATE - INTERVAL '7 days'
           ORDER BY date DESC`
        );
        return { content: [{ type: "text", text: JSON.stringify(trends) }] };
      }

      case "get_active_meals": {
        const meals = await query(
          `SELECT id, name, portions_remaining, total_portions,
                  calories_per_portion, protein_per_portion, prep_date
           FROM nutrition.meals
           WHERE portions_remaining > 0
           ORDER BY prep_date DESC`
        );
        return { content: [{ type: "text", text: JSON.stringify(meals) }] };
      }

      case "get_shopping_list": {
        const items = await query(
          `SELECT sli.item_name, sli.quantity, sli.unit, sli.is_purchased, sli.category
           FROM nutrition.shopping_list_items sli
           JOIN nutrition.shopping_lists sl ON sli.list_id = sl.id
           WHERE sl.status = 'active'
           ORDER BY sli.category, sli.item_name`
        );
        return { content: [{ type: "text", text: JSON.stringify(items) }] };
      }

      case "get_low_stock": {
        const items = await query(`SELECT * FROM nutrition.low_stock`);
        return { content: [{ type: "text", text: JSON.stringify(items) }] };
      }

      case "get_habits_today": {
        const habits = await query(
          `SELECT h.name, h.category, h.current_streak,
                  COALESCE(hl.completed, FALSE) as completed_today
           FROM activity.habits h
           LEFT JOIN activity.habit_log hl ON h.id = hl.habit_id AND hl.date = CURRENT_DATE
           WHERE h.is_active = TRUE
           ORDER BY h.category, h.name`
        );
        return { content: [{ type: "text", text: JSON.stringify(habits) }] };
      }

      case "search_food_history": {
        const results = await query(
          `SELECT date, meal_time, description, calories, protein_g
           FROM nutrition.food_log
           WHERE description ILIKE $1
             AND date >= CURRENT_DATE - INTERVAL '${args.days || 30} days'
           ORDER BY date DESC
           LIMIT 20`,
          [`%${args.query}%`]
        );
        return { content: [{ type: "text", text: JSON.stringify(results) }] };
      }

      case "query_nexus": {
        // Safety check - only allow SELECT
        if (!args.sql.trim().toUpperCase().startsWith("SELECT")) {
          return {
            content: [
              { type: "text", text: JSON.stringify({ error: "Only SELECT queries allowed" }) },
            ],
          };
        }
        const results = await query(args.sql);
        return { content: [{ type: "text", text: JSON.stringify(results) }] };
      }

      default:
        return { content: [{ type: "text", text: JSON.stringify({ error: "Unknown tool" }) }] };
    }
  } catch (error) {
    return {
      content: [{ type: "text", text: JSON.stringify({ error: error.message }) }],
      isError: true,
    };
  }
});

// =============================================================================
// RESOURCES - Data Claude can read
// =============================================================================

server.setRequestHandler(ListResourcesRequestSchema, async () => {
  return {
    resources: [
      {
        uri: "nexus://today/summary",
        name: "Today's Summary",
        description: "Current day health, nutrition, and activity summary",
        mimeType: "application/json",
      },
      {
        uri: "nexus://goals/active",
        name: "Active Goals",
        description: "Current active goals and progress",
        mimeType: "application/json",
      },
      {
        uri: "nexus://meals/active",
        name: "Active Batch Meals",
        description: "Batch meals with remaining portions",
        mimeType: "application/json",
      },
    ],
  };
});

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;

  switch (uri) {
    case "nexus://today/summary": {
      const data = await query(`SELECT * FROM core.daily_summary WHERE date = CURRENT_DATE`);
      return { contents: [{ uri, mimeType: "application/json", text: JSON.stringify(data[0] || {}) }] };
    }
    case "nexus://goals/active": {
      const data = await query(`SELECT * FROM core.goals WHERE status = 'active'`);
      return { contents: [{ uri, mimeType: "application/json", text: JSON.stringify(data) }] };
    }
    case "nexus://meals/active": {
      const data = await query(`SELECT * FROM nutrition.meals WHERE portions_remaining > 0`);
      return { contents: [{ uri, mimeType: "application/json", text: JSON.stringify(data) }] };
    }
    default:
      throw new Error(`Unknown resource: ${uri}`);
  }
});

// =============================================================================
// HELPERS
// =============================================================================

function inferMealTime() {
  const hour = new Date().getHours();
  if (hour < 10) return "breakfast";
  if (hour < 14) return "lunch";
  if (hour < 17) return "snack";
  return "dinner";
}

// =============================================================================
// START SERVER
// =============================================================================

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Nexus MCP server running");
}

main().catch(console.error);
