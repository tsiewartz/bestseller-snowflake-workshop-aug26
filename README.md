# Bestseller Snowflake Workshop – August 26


## What we're building this afternoon

By 13:50 you'll have assembled one connected system:

- **Block 1** – Two governed Cortex Agents, accessible from Claude Desktop via a single MCP connection
- **Block 2** – A dbt pipeline running natively in Snowflake, modelling the data those agents query
- **Block 3** – A governed app that calls the agents you built in Block 1 and shows only role-appropriate data

The app talks to the agents. The agents query the modelled data. Governance is enforced automatically at every layer. Nothing in the app code manages access.

**Post to the shared channel as you go:** When you complete Block 1, post your MCP server URL. When you complete Block 3, post your app URL. By the end of the afternoon the channel is a record of what the group built.

---

## Block 1 – 12:10–12:45 (35 min)
### One connection, multiple agents: MCP in practice

**North Star:** Can you ask two different agents from one Claude Desktop connection and get role-appropriate answers from each?

**Prereqs – confirm before starting:**
- Claude Desktop installed
- MCP server URL from Trine
- OAuth client ID + secret from Trine

**Steps:**

1. Configure the MCP connection in Claude Desktop:
   - Open Settings → Connectors → Add custom connector
   - Paste the MCP server URL and OAuth credentials
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

**Try to break it:** Ask Agent A a question that belongs to Agent B's domain. Does it leak data or stay in scope? Tune the system prompt until the boundary holds.

**Stretch – agent versioning:** Create a second version of one of your agents with a modified system prompt. Run both versions simultaneously from the same MCP connection, one as `LIVE` and one as `EXPERIMENTAL`. This is how you safely iterate on agents in production without breaking the live version.
```sql
-- After editing the agent, commit a new version
ALTER CORTEX AGENT WORKSHOP_DB.AI.BRAND_AGENT ADD VERSION v2 FROM LIVE;
ALTER CORTEX AGENT WORKSHOP_DB.AI.BRAND_AGENT SET DEFAULT VERSION = v1;
```

**Post to the shared channel:** your MCP server URL.

---

## Block 2 – 12:45–13:20 (35 min)
### Run dbt natively in Snowflake

**North Star:** Can you run your dbt models natively in Snowflake and see the lineage in Snowsight?

**Prereqs – confirm before starting:**
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

3. Verify in Snowsight: open Query History – the dbt models ran as Snowflake-native tasks with no external orchestrator.

4. Check lineage: Snowsight → Data → Lineage – the dbt output tables show their upstream dependencies.

5. Schedule on a Task:
```sql
CREATE TASK RUN_DBT_DAILY
  WAREHOUSE = WORKSHOP_WH
  SCHEDULE = 'USING CRON 0 6 * * * UTC'
AS
  EXECUTE DBT PROJECT WORKSHOP_DB.PUBLIC.WORKSHOP_DBT;
```

**Stretch:** Compare `snow dbt execute` run time vs. your existing pipeline for the same models.

---

## Block 3 – 13:20–13:50 (30 min)
### Ship it: a governed app in 30 minutes

**North Star:** Does the same app URL return different data for two different Snowflake users?

**Goal:** Build an app that calls the agents from Block 1 and shows role-appropriate data. The app inherits the user's Snowflake session role. All governance applies automatically with no access logic in the app code.

Choose your path:

---

### Path A – React App Runtime (CLI)
*Prereqs: Node 18+, `snow` CLI configured*

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

3. Add session identity to the UI – open `src/app/page.tsx` and add:
```ts
const identity = await snowflake.execute(
  'SELECT CURRENT_USER() AS user, CURRENT_ROLE() AS role'
);
// Render user and role prominently in the UI
```

4. Add a call to your Block 1 agent — create `src/app/api/ask/route.ts`:
```
POST /api/v2/cortex/agents/WORKSHOP_DB.AI.BRAND_AGENT:run
Body: { messages: [{ role: "user", content: question }] }
```
Add a text input + response in `src/app/page.tsx`.

5. Run:
```bash
snow app run
```

6. Deploy if time allows:
```bash
snow app deploy
```

---

### Path B – Streamlit in Snowflake (Snowsight)
*No local setup required. Fully deployed by end of session.*

1. Open Snowsight → Projects → Streamlit → + Streamlit App

2. Paste and adapt:
```python
import streamlit as st
import requests
from snowflake.snowpark.context import get_active_session

session = get_active_session()

# Show session identity – makes role inheritance visible
identity = session.sql(
    "SELECT CURRENT_USER() AS user, CURRENT_ROLE() AS role"
).collect()[0]
st.caption(f"Logged in as {identity['USER']} · Role: {identity['ROLE']}")

st.title("Bestseller Data App")

# Governed table – RAP applies automatically
df = session.sql("SELECT * FROM <your_governed_table> LIMIT 100").to_pandas()
st.dataframe(df)

st.divider()

# Call the agent from Block 1
question = st.text_input("Ask a question about your data")
if question:
    token = session.sql("SELECT SYSTEM$USER_ACCESS_TOKEN()").collect()[0][0]
    response = requests.post(
        "https://<account>.snowflakecomputing.com/api/v2/cortex/agents/WORKSHOP_DB.AI.BRAND_AGENT:run",
        headers={"Authorization": f"Bearer {token}"},
        json={"messages": [{"role": "user", "content": question}]}
    )
    st.write(response.json().get("message", {}).get("content", ""))
```

3. Click Run. App is live inside Snowflake.

---

**Try to break it:** Open the app in a second browser window as a different Snowflake user. Do you see different data? Try to get the app to show data outside your role's access. It shouldn't be possible – governance is enforced on the Snowflake side, not in the app.

**Post to the shared channel:** your app URL.

---

Both paths end the same way: a running app, calling governed agents, showing role-appropriate data. Demo both to the room at 13:50.

---

## Admin Setup – one person at Bestseller, before the day

See [admin-setup.sql](admin-setup.sql) for the full SQL. The file walks through 8 steps with verification checks at each stage.

**Summary of what needs to happen:**

1. **Verify features** – run the check queries in Step 1 of admin-setup.sql to confirm Cortex AI, CoWork, MCP servers, and compute pools are available on your account. If anything fails, contact Trine before the day.

2. **Identify two tables** – pick 1-2 real but non-critical tables that have:
   - A categorical column (brand, market, department, region) — used for the agent scope demo
   - A date column + a numeric measure (revenue, units, headcount) — used for the AI analytics demo
   Note the full paths (`database.schema.table`) and share with Trine before the day.

3. **Create workshop infrastructure** – run Steps 3-6 in admin-setup.sql. This creates `WORKSHOP_DB`, `WORKSHOP_ROLE`, `WORKSHOP_WH`, a compute pool, the MCP OAuth integration, and the MCP server skeleton.

4. **Create a dedicated role** – `WORKSHOP_ROLE` is created by the script. Using a dedicated role keeps workshop activity isolated from production and makes cleanup easy afterwards. Do not reuse an existing production role.

5. **Configure each participant** – for every attendee, run:
```sql
GRANT ROLE WORKSHOP_ROLE TO USER <username>;
ALTER USER <username>
  SET DEFAULT_ROLE = 'WORKSHOP_ROLE'
      DEFAULT_WAREHOUSE = 'WORKSHOP_WH';
```
The `DEFAULT_ROLE` setting is required for MCP. Claude uses the default role, not the active role.

6. **Check network policy** – if your Snowflake account has a network policy, Claude's outbound IPs must be allowed. See Step 8 in admin-setup.sql. Get Anthropic's current IP list from docs.anthropic.com/en/docs/resources/ip-addresses.

**MCP server URL to share with participants on the day:**
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
- [ ] Snowflake CLI: `brew install snowflake-cli`
- [ ] Configure connection: `snow connection add`
- [ ] Test: `snow connection test`

**Block 2 (dbt) only:**
- [ ] Snowflake CLI installed and connection working (same as above)
- [ ] Bring your dbt project or confirm access to the example project
