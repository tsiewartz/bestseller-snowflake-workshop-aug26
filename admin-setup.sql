-- ============================================================
-- Bestseller Workshop — Admin Setup
-- Run as ACCOUNTADMIN before the workshop day
-- One person at Bestseller completes all steps below
-- ============================================================


-- ============================================================
-- STEP 1: Verify features are available on this account
-- Run each check and confirm no errors before proceeding
-- ============================================================

-- 1a. Cortex AI (required for agents and Cortex Analyst)
SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-7b', 'hello');
-- Expected: a short text response. If this errors, contact Trine before the day.

-- 1b. Snowflake Intelligence / CoWork
-- Check in Snowsight: Admin → Feature Preview → confirm "Snowflake Intelligence" is enabled
-- If not visible, contact Trine — it requires account-level enablement.

-- 1c. MCP Server support
SHOW MCP SERVERS IN ACCOUNT;
-- Expected: empty result (no servers yet) or existing servers. If command fails, contact Trine.

-- 1d. Compute pools / App Runtime (required for Path A of Block 3)
SHOW COMPUTE POOLS;
-- Expected: any result (empty is fine). If command errors with "not supported", Path A is
-- unavailable on this account — participants will use Path B (Streamlit) instead.

-- 1e. dbt in Snowflake (required for Block 2)
SHOW DBT PROJECTS IN ACCOUNT;
-- Expected: empty result or existing projects. If command fails, contact Trine.

-- 1f. Account edition (Row Access Policies require Enterprise or higher)
SELECT CURRENT_VERSION(), SYSTEM$BOOTSTRAP_DATA_REQUEST('ACCOUNT');
-- Or check Snowsight: Admin → Account → Edition


-- ============================================================
-- STEP 2: Identify the data to use
-- Before running anything below, decide on:
--   TABLE_A: a table with a categorical column (brand, market, department, region)
--            and at least one numeric measure — used for governance and AI demos
--   TABLE_B: optionally a second table for the second agent's domain
-- These should be real but non-critical tables (not directly in production pipelines)
-- Note the full paths: <database>.<schema>.<table>
-- ============================================================


-- ============================================================
-- STEP 3: Create workshop infrastructure
-- Run as ACCOUNTADMIN or SYSADMIN
-- ============================================================

-- Workshop database and schemas
CREATE DATABASE IF NOT EXISTS WORKSHOP_DB;
CREATE SCHEMA IF NOT EXISTS WORKSHOP_DB.AI;
CREATE SCHEMA IF NOT EXISTS WORKSHOP_DB.APP;

-- Dedicated workshop role
-- Why a new role: isolates workshop activity from production roles,
-- easy to clean up after, and prevents accidental privilege escalation
CREATE ROLE IF NOT EXISTS WORKSHOP_ROLE;
GRANT ROLE WORKSHOP_ROLE TO ROLE SYSADMIN;

-- Privileges on workshop objects
GRANT ALL ON DATABASE WORKSHOP_DB TO ROLE WORKSHOP_ROLE;
GRANT ALL ON ALL SCHEMAS IN DATABASE WORKSHOP_DB TO ROLE WORKSHOP_ROLE;
GRANT ALL ON FUTURE SCHEMAS IN DATABASE WORKSHOP_DB TO ROLE WORKSHOP_ROLE;
GRANT ALL ON FUTURE TABLES IN DATABASE WORKSHOP_DB TO ROLE WORKSHOP_ROLE;

-- Dedicated warehouse (small — workshop queries are light)
CREATE WAREHOUSE IF NOT EXISTS WORKSHOP_WH
  WAREHOUSE_SIZE = 'SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;
GRANT USAGE ON WAREHOUSE WORKSHOP_WH TO ROLE WORKSHOP_ROLE;

-- Cortex AI usage
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE WORKSHOP_ROLE;

-- Compute pool for React App Runtime (Path A of Block 3)
-- Skip this block if SHOW COMPUTE POOLS failed in Step 1
CREATE COMPUTE POOL IF NOT EXISTS WORKSHOP_POOL
  MIN_NODES = 1
  MAX_NODES = 3
  INSTANCE_FAMILY = CPU_X64_XS;
GRANT USAGE ON COMPUTE POOL WORKSHOP_POOL TO ROLE WORKSHOP_ROLE;

-- Start the compute pool now so it's warm on the day
ALTER COMPUTE POOL WORKSHOP_POOL RESUME;


-- ============================================================
-- STEP 4: Grant access to your data tables
-- Replace with the actual table paths identified in Step 2
-- ============================================================

GRANT USAGE ON DATABASE <your_db> TO ROLE WORKSHOP_ROLE;
GRANT USAGE ON SCHEMA <your_db>.<your_schema> TO ROLE WORKSHOP_ROLE;
GRANT SELECT ON TABLE <your_db>.<your_schema>.<table_a> TO ROLE WORKSHOP_ROLE;
-- Repeat for TABLE_B if using a second table


-- ============================================================
-- STEP 5: Set up MCP OAuth integration
-- ============================================================

CREATE OR REPLACE SECURITY INTEGRATION WORKSHOP_MCP_OAUTH
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback';

-- Retrieve and save the client ID and secret — share with Trine before the day
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('WORKSHOP_MCP_OAUTH');


-- ============================================================
-- STEP 6: Create the MCP server
-- Note: create the two agents in Snowflake Intelligence FIRST (Block 1 build),
-- then run this block to register them. This can be done on the day.
-- ============================================================

CREATE OR REPLACE MCP SERVER WORKSHOP_DB.AI.WORKSHOP_MCP_SERVER
  FROM SPECIFICATION $$
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

GRANT USAGE ON MCP SERVER WORKSHOP_DB.AI.WORKSHOP_MCP_SERVER TO ROLE WORKSHOP_ROLE;

-- MCP server URL to share with participants:
-- https://<org>-<account>.snowflakecomputing.com/api/v2/databases/WORKSHOP_DB/schemas/AI/mcp-servers/WORKSHOP_MCP_SERVER
-- Use hyphens (-) not underscores (_) in the account URL


-- ============================================================
-- STEP 7: Configure each participant's user
-- Run for every participant who will attend the session
-- ============================================================

-- Grant the workshop role to each user
GRANT ROLE WORKSHOP_ROLE TO USER <username>;

-- Set default role and warehouse
-- This is required for MCP — Claude uses DEFAULT_ROLE, not the active role
ALTER USER <username>
  SET DEFAULT_ROLE = 'WORKSHOP_ROLE'
      DEFAULT_WAREHOUSE = 'WORKSHOP_WH';

-- Repeat the two statements above for each participant


-- ============================================================
-- STEP 8: Network policy check (if your account has one)
-- If Bestseller uses a network policy, Claude's outbound IPs must be allowed.
-- Check current policies:
-- ============================================================

SHOW NETWORK POLICIES;

-- If a policy is attached to the account, add Anthropic's IPs:
-- Get the current IP list from: https://docs.anthropic.com/en/docs/resources/ip-addresses
-- Then:
-- CREATE NETWORK RULE CLAUDE_INGRESS_RULE
--   MODE = INGRESS TYPE = IPV4
--   VALUE_LIST = ('<anthropic_ip_1>', '<anthropic_ip_2>', ...);
-- ALTER NETWORK POLICY <your_policy> ADD ALLOWED_NETWORK_RULE_LIST = ('CLAUDE_INGRESS_RULE');


-- ============================================================
-- CLEANUP after the workshop (run when done)
-- ============================================================

-- DROP DATABASE WORKSHOP_DB;
-- DROP WAREHOUSE WORKSHOP_WH;
-- DROP COMPUTE POOL WORKSHOP_POOL;
-- DROP ROLE WORKSHOP_ROLE;
-- DROP SECURITY INTEGRATION WORKSHOP_MCP_OAUTH;
