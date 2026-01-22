# Nexus MCP Server

MCP (Model Context Protocol) server that gives Claude direct access to your Nexus database.

## Installation

```bash
cd /Users/rafa/Cyber/Infrastructure/Nexus-setup/mcp-server
npm install
```

## Configuration

Add to your Claude Code MCP config (`~/.claude/claude_desktop_config.json` or Claude Code settings):

```json
{
  "mcpServers": {
    "nexus": {
      "command": "node",
      "args": ["/Users/rafa/Cyber/Infrastructure/Nexus-setup/mcp-server/index.js"],
      "env": {
        "NEXUS_HOST": "nexus",
        "NEXUS_PORT": "5432",
        "NEXUS_DB": "nexus",
        "NEXUS_USER": "nexus",
        "NEXUS_PASSWORD": "YOUR_PASSWORD_HERE"
      }
    }
  }
}
```

Or use Tailscale hostname:
```json
"NEXUS_HOST": "nexus.tailnet-name.ts.net"
```

## Available Tools

### Food Logging
| Tool | Description | Example |
|------|-------------|---------|
| `log_food` | Log any food | "2 eggs and toast for breakfast" |
| `log_batch_meal` | Create batch meal | "Chicken stir fry, 5 portions" |
| `log_water` | Log water intake | 250ml or 1 glass |

### Health
| Tool | Description |
|------|-------------|
| `log_weight` | Log body weight |
| `log_metric` | Log any health metric |
| `log_supplement` | Log supplement taken |

### Mood & Habits
| Tool | Description |
|------|-------------|
| `log_mood` | Log mood/energy/stress (1-10) |
| `log_habit` | Mark habit complete |

### Shopping & Pantry
| Tool | Description |
|------|-------------|
| `add_to_shopping_list` | Add items to list |
| `update_pantry` | Add/remove/use pantry items |

### Queries
| Tool | Description |
|------|-------------|
| `get_today_summary` | Today's overview |
| `get_nutrition_today` | Detailed food log |
| `get_weekly_trends` | 7-day trends |
| `get_active_meals` | Batch meals with portions |
| `get_shopping_list` | Current shopping list |
| `get_habits_today` | Habit completion status |
| `query_nexus` | Custom SQL (SELECT only) |

## Natural Language Examples

Once configured, just talk to Claude naturally:

```
"Log breakfast: 2 eggs, avocado toast, coffee"
"I just had the chicken stir fry, serving 3"
"Add milk, eggs, and spinach to my shopping list"
"How much protein have I had today?"
"What's my recovery been like this week?"
"Mark meditation as done"
"Log mood: 7, energy: 6, feeling good but tired"
"Show me what I ate yesterday"
"What batch meals do I have left?"
```

## Resources

The server also exposes these as readable resources:
- `nexus://today/summary` - Today's complete summary
- `nexus://goals/active` - Active goals
- `nexus://meals/active` - Batch meals with portions

## Testing

```bash
# Set environment variables
export NEXUS_PASSWORD="your_password"
export NEXUS_HOST="localhost"

# Run directly (will wait for MCP input)
node index.js
```
