# Bestseller Snowflake Workshop — August 26

Hands-on session guide for three afternoon workshop blocks.

## Agenda

| Time | Block |
|---|---|
| 12:00–12:45 | [Block 1: MCP Configuration](#block-1--1200-1245-45-min) |
| 12:45–13:20 | [Block 2: dbt Project in Snowflake](#block-2--1245-1320-35-min) |
| 13:20–13:50 | [Block 3: Governed App Deployment](#block-3--1320-1350-30-min) |

---

## Block 1 — 12:00–12:45 (45 min)
### MCP Configuration: Multiple Cortex Agents Behind a Single Connection

**Goal:** Two Cortex Agents with different data scopes, both reachable through a single MCP connection in Claude Desktop.

**Prereqs — confirm before starting:**
- Claude Desktop installed
- MCP server URL from Trine
- OAuth client ID + secret from Trine

**Steps:**

1. Configure the MCP connection in Claude Desktop:
   - Open Settings → Connectors → Add custom connector
   - Paste the MCP server URL
   - Paste the OAuth client ID and secret
   - Click Add → browser opens → log in to Snowflake → approve consent screen
   - Verify: Snowflake tools appear in Claude

2. Create Agent A in Snowflake Intelligence:
   - Name: e.g. `BRAND_AGENT`
   - System prompt: scoped to brand performance (2-3 sentences, domain-specific)
   - Tool: Cortex Analyst → semantic view
   - Runs as: a role that sees brand data

3. Create Agent B:
   - Name: e.g. `SUPPLY_AGENT`
   - System prompt: scoped to a different domain
   - Runs as: a role with different data access

4. Register both agents in the MCP server:
```sql
ALTER MCP SERVER WORKSHOP_MCP_SERVER SET SPECIFICATION = $$
  tools:
    - name: "brand-agent"
      type: "CORTEX_AGENT_RUN"
      identifier: "WORKSHOP_DB.AI.BRAND_AGENT"
      description: "Agent for brand performance questions"
    - name: "supply-agent"
      type: "CORTEX_AGENT_RUN"
      identifier: "WORKSHOP_DB.AI.SUPPLY_AGENT"
      description: "Agent for supply chain questions"
$$;
```

5. From Claude Desktop, ask each agent a domain-specific question. Confirm they stay in their lane and return role-appropriate data.

**Stretch:** Ask Agent A a question that belongs to Agent B's domain. Observe the behaviour. Tune the system prompt to handle the boundary case — this is the most realistic production problem.

---

## Block 2 — 12:45–13:20 (35 min)
### dbt Project in Snowflake

**Goal:** Deploy a dbt project as a Snowflake-native object and run it without an external orchestrator.

**Prereqs — confirm before starting:**
- `snow` CLI configured: `snow connection test`
- An existing dbt project, or use a minimal 2-model example

**Steps:**

1. Deploy the project:
```bash
snow dbt deploy --project-dir <path> --name WORKSHOP_DBT
```

2. Run it:
```bash
snow dbt execute --name WORKSHOP_DBT
```

3. Verify in Snowsight: open Query History — the dbt models ran as Snowflake-native tasks, no external orchestrator involved.

4. Check lineage: Snowsight → Data → Lineage — the dbt output tables show their upstream dependencies.

5. Schedule on a Task:
```sql
CREATE TASK RUN_DBT_DAILY
  WAREHOUSE = WORKSHOP_WH
  SCHEDULE = 'USING CRON 0 6 * * * UTC'
AS
  EXECUTE DBT PROJECT WORKSHOP_DB.PUBLIC.WORKSHOP_DBT;
```

**Stretch:** Compare `snow dbt execute` run time vs. your current Airflow DAG for the same models.

---

## Block 3 — 13:20–13:50 (30 min)
### Governed App Deployment

**Goal:** Build an app connected to governed Snowflake data and a Cortex Agent. The app inherits the user's session role — all governance applies automatically, no access logic in the app code.

Choose your path:

---

### Path A — React App Runtime (CLI)
*Target: local running app (`snow app run`). Skip deploy — 30 min is not enough to deploy.*

**Prereqs:** Node 18+, Docker Desktop running, `snow` CLI configured

1. Scaffold:
```bash
snow app init BESTSELLER_APP --template basic-react
cd BESTSELLER_APP && npm install
```

2. Open `src/app/api/data/route.ts`, replace the sample query:
```ts
const result = await snowflake.execute(
  'SELECT * FROM <your_governed_table> LIMIT 100'
);
```

3. Add a Cortex Agent call — create `src/app/api/ask/route.ts`:
```
POST /api/v2/cortex/agents/<agent_name>:run
Body: { messages: [{ role: "user", content: question }] }
```
Add a text input + response in `src/app/page.tsx`.

4. Run:
```bash
snow app run
```
App opens in browser. Verify the table data is filtered by your role.

**Stretch:** `snow app deploy` if time allows.

---

### Path B — Streamlit in Snowflake (Snowsight)
*No local setup required. Fully deployed by end of session.*

1. Open Snowsight → Projects → Streamlit → + Streamlit App

2. Paste and adapt:
```python
import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()

st.title("Bestseller Data App")

df = session.sql("SELECT * FROM <your_governed_table> LIMIT 100").to_pandas()
st.dataframe(df)

st.divider()
question = st.text_input("Ask a question about your data")
if question:
    response = session.sql(f"""
        SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-7b', '{question}')
    """).collect()
    st.write(response[0][0])
```

3. Click Run. App is live inside Snowflake.

4. Test: open the app as a different user or switch your role — confirm the table data changes accordingly.

**Stretch:** Replace `CORTEX.COMPLETE` with a proper Cortex Agent REST call for a scoped, governed response.

---

Both paths end the same way: a running app where governance is enforced by the Snowflake session, not the app. Demo both to the room at 13:50.

---

## Admin Setup

See [admin-setup.sql](admin-setup.sql) — run this before the day.

**MCP server URL to share with participants:**
```
https://<org>-<account>.snowflakecomputing.com/api/v2/databases/WORKSHOP_DB/schemas/AI/mcp-servers/WORKSHOP_MCP_SERVER
```
Use hyphens not underscores in the account URL.

---

## Participant Prework

**Everyone:**
- [ ] Log in to Snowsight and confirm you can switch to `WORKSHOP_ROLE`
- [ ] Install Claude Desktop: https://claude.ai/download

**Path A (React App Runtime) only:**
- [ ] Node.js 18+: `node --version`
- [ ] Docker Desktop installed and running
- [ ] Snowflake CLI: `brew install snowflake-cli`
- [ ] Configure connection: `snow connection add`
- [ ] Test: `snow connection test`

**Block 2 (dbt) only:**
- [ ] Snowflake CLI installed and connection working (same as above)
- [ ] Bring your dbt project or confirm access to the example project
