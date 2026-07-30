-- ============================================================
-- Bestseller Workshop — Admin Setup
-- Run as ACCOUNTADMIN before the workshop day
-- ============================================================

-- Workshop database and schemas
CREATE DATABASE WORKSHOP_DB;
CREATE SCHEMA WORKSHOP_DB.AI;
CREATE SCHEMA WORKSHOP_DB.APP;

-- Workshop role
CREATE ROLE WORKSHOP_ROLE;
GRANT ROLE WORKSHOP_ROLE TO ROLE SYSADMIN;
GRANT ALL ON DATABASE WORKSHOP_DB TO ROLE WORKSHOP_ROLE;
GRANT ALL ON ALL SCHEMAS IN DATABASE WORKSHOP_DB TO ROLE WORKSHOP_ROLE;
GRANT ALL ON FUTURE SCHEMAS IN DATABASE WORKSHOP_DB TO ROLE WORKSHOP_ROLE;

-- Warehouse
CREATE WAREHOUSE WORKSHOP_WH WAREHOUSE_SIZE = 'SMALL' AUTO_SUSPEND = 60;
GRANT USAGE ON WAREHOUSE WORKSHOP_WH TO ROLE WORKSHOP_ROLE;

-- Compute pool for React App Runtime (Path A)
CREATE COMPUTE POOL WORKSHOP_POOL
  MIN_NODES = 1 MAX_NODES = 3
  INSTANCE_FAMILY = CPU_X64_XS;
GRANT USAGE ON COMPUTE POOL WORKSHOP_POOL TO ROLE WORKSHOP_ROLE;

-- MCP OAuth integration
CREATE SECURITY INTEGRATION WORKSHOP_MCP_OAUTH
  TYPE = OAUTH
  OAUTH_CLIENT = CUSTOM
  ENABLED = TRUE
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'https://claude.ai/api/mcp/auth_callback';

-- Retrieve client ID and secret to share with participants
SELECT SYSTEM$SHOW_OAUTH_CLIENT_SECRETS('WORKSHOP_MCP_OAUTH');

-- MCP server
-- Note: create BRAND_AGENT and SUPPLY_AGENT in Snowflake Intelligence first,
-- then update the identifiers below before running this block
CREATE MCP SERVER WORKSHOP_DB.AI.WORKSHOP_MCP_SERVER
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

-- Set DEFAULT_ROLE and DEFAULT_WAREHOUSE for each participant
-- (repeat for each participant username)
ALTER USER <username> SET DEFAULT_ROLE = 'WORKSHOP_ROLE'
                           DEFAULT_WAREHOUSE = 'WORKSHOP_WH';

-- Grant SELECT on governed tables
-- (replace with actual table paths from prework)
GRANT SELECT ON TABLE <db>.<schema>.<table> TO ROLE WORKSHOP_ROLE;

-- MCP server URL to share with participants:
-- https://<org>-<account>.snowflakecomputing.com/api/v2/databases/WORKSHOP_DB/schemas/AI/mcp-servers/WORKSHOP_MCP_SERVER
-- Use hyphens not underscores in the account URL
