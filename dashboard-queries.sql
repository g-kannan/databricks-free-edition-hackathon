-- ============================================
-- N8N DASHBOARD SQL QUERIES
-- https://docs.n8n.io/hosting/architecture/database-structure/
-- ============================================

-- 1. WORKFLOW EXECUTION OVERVIEW (Last 30 Days)
-- Shows success rate, total executions, and average duration
SELECT 
    COUNT(*) as total_executions,
    SUM(CASE WHEN finished = true THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN finished = false OR stoppedAt IS NULL THEN 1 ELSE 0 END) as failed,
    ROUND(100.0 * SUM(CASE WHEN finished = true THEN 1 ELSE 0 END) / COUNT(*), 2) as success_rate_percent,
    ROUND(AVG(
        unix_seconds(stoppedAt) - unix_seconds(startedAt)
    ), 2) as avg_duration_seconds
FROM execution_entity
WHERE startedAt >= NOW() - INTERVAL '30 days';

-- 2. TOP 10 MOST EXECUTED WORKFLOWS
-- Identifies your most active workflows
SELECT 
    w.id,
    w.name,
    COUNT(e.id) as execution_count,
    SUM(CASE WHEN e.finished = true THEN 1 ELSE 0 END) as successful_runs,
    ROUND(
        100.0 * SUM(CASE WHEN e.finished = true THEN 1 ELSE 0 END) / COUNT(e.id),
        2
    ) as success_rate,
    w.active
FROM workflow_entity w
LEFT JOIN execution_entity e ON e.workflowId = w.id
WHERE e.startedAt >= NOW() - INTERVAL 30 DAYS
GROUP BY w.id, w.name, w.active
ORDER BY execution_count DESC
LIMIT 10

-- 3. WORKFLOWS WITH HIGHEST FAILURE RATES
-- Critical for identifying problematic workflows
SELECT 
    w.id,
    w.name,
    COUNT(e.id) as total_executions,
    SUM(CASE WHEN e.finished = false THEN 1 ELSE 0 END) as failed_executions,
    ROUND(100.0 * SUM(CASE WHEN e.finished = false THEN 1 ELSE 0 END) / COUNT(e.id), 2) as failure_rate_percent
FROM workflow_entity w
INNER JOIN execution_entity e ON e.workflowId = w.id
WHERE e.startedAt >= NOW() - INTERVAL 7 DAYS
GROUP BY w.id, w.name
HAVING COUNT(e.id) >= 5
ORDER BY failure_rate_percent DESC
LIMIT 10;

-- 4. EXECUTION TRENDS BY DAY (Last 30 Days)
-- Visualize execution patterns over time
SELECT 
    DATE(startedAt) as execution_date,
    COUNT(*) as total_executions,
    SUM(CASE WHEN finished = true THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN finished = false THEN 1 ELSE 0 END) as failed
FROM execution_entity
WHERE startedAt >= NOW() - INTERVAL 30 DAYS
GROUP BY DATE(startedAt)
ORDER BY execution_date DESC;

-- 5. EXECUTION TRENDS BY HOUR (Last 7 Days)
-- Identify peak usage times
SELECT 
    HOUR(startedAt) as hour_of_day,
    COUNT(*) as execution_count,
    ROUND(AVG(unix_seconds(stoppedAt) - unix_seconds(startedAt)), 2) as avg_duration_seconds
FROM execution_entity
WHERE startedAt >= NOW() - INTERVAL 7 DAYS
GROUP BY HOUR(startedAt)
ORDER BY hour_of_day;

-- 6. SLOWEST WORKFLOWS (Average Duration)
-- Performance optimization targets
SELECT 
    w.id,
    w.name,
    COUNT(e.id) as execution_count,
    ROUND(AVG(unix_seconds(e.stoppedAt) - unix_seconds(e.startedAt)), 2) as avg_duration_seconds,
    ROUND(MAX(unix_seconds(e.stoppedAt) - unix_seconds(e.startedAt)), 2) as max_duration_seconds,
    ROUND(MIN(unix_seconds(e.stoppedAt) - unix_seconds(e.startedAt)), 2) as min_duration_seconds
FROM workflow_entity w
INNER JOIN execution_entity e ON e.workflowId = w.id
WHERE e.startedAt >= NOW() - INTERVAL 30 DAYS
    AND e.stoppedAt IS NOT NULL
GROUP BY w.id, w.name
HAVING COUNT(e.id) >= 5
ORDER BY avg_duration_seconds DESC
LIMIT 10;

-- 7. RECENT FAILED EXECUTIONS WITH ERROR DETAILS
-- Quick troubleshooting view
SELECT 
    e.id,
    w.name as workflow_name,
    e.startedAt,
    e.stoppedAt,
    e.mode,
    e.waitTill,
    unix_seconds(e.stoppedAt) - unix_seconds(e.startedAt) as duration_seconds
FROM execution_entity e
INNER JOIN workflow_entity w ON e.workflowId = w.id
WHERE e.finished = false
    AND e.startedAt >= NOW() - INTERVAL 7 DAYS
ORDER BY e.startedAt DESC
LIMIT 20;

-- 8. ACTIVE WORKFLOWS STATUS
-- Overview of all active workflows
SELECT 
    w.id,
    w.name,
    w.active,
    w.createdAt,
    w.updatedAt,
    COUNT(e.id) as total_executions,
    MAX(e.startedAt) as last_execution
FROM workflow_entity w
LEFT JOIN execution_entity e ON e.workflowId = w.id
WHERE w.active = true
GROUP BY w.id, w.name, w.active, w.createdAt, w.updatedAt
ORDER BY last_execution DESC NULLS LAST;

-- 9. EXECUTION MODE BREAKDOWN
-- Understanding how workflows are triggered
SELECT 
    mode,
    COUNT(*) as execution_count,
    SUM(CASE WHEN finished = true THEN 1 ELSE 0 END) as successful,
    ROUND(100.0 * SUM(CASE WHEN finished = true THEN 1 ELSE 0 END) / COUNT(*), 2) as success_rate_percent
FROM execution_entity
WHERE startedAt >= NOW() - INTERVAL 30 DAYS
GROUP BY mode
ORDER BY execution_count DESC;

-- 10. WAITING EXECUTIONS
-- Monitor queued/delayed executions
SELECT 
    e.id,
    w.name as workflow_name,
    e.waitTill,
    e.startedAt,
    e.mode
FROM execution_entity e
INNER JOIN workflow_entity w ON e.workflowId = w.id
WHERE e.waitTill IS NOT NULL
    AND e.finished = false
ORDER BY e.waitTill ASC;

-- 11. CREDENTIALS USAGE
-- Track which credentials are being used
SELECT 
    c.name,
    c.type,
    COUNT(DISTINCT w.id) as workflows_using,
    c.createdAt,
    c.updatedAt
FROM credentials_entity c
LEFT JOIN workflow_entity w ON w.nodes LIKE CONCAT('%', c.id, '%')
GROUP BY c.id, c.name, c.type, c.createdAt, c.updatedAt
ORDER BY workflows_using DESC;

-- 12. WORKFLOW TAGS SUMMARY
-- Organize workflows by tags
SELECT 
    t.name as tag_name,
    COUNT(DISTINCT wtm.workflowId) as workflow_count
FROM tag_entity t
INNER JOIN workflows_tags_tag_entity wtm ON t.id = wtm.tagId
GROUP BY t.id, t.name
ORDER BY workflow_count DESC;

-- 13. EXECUTION DATA SIZE ANALYSIS
-- Monitor data volume being processed
SELECT 
    w.name as workflow_name,
    COUNT(e.id) as execution_count,
    ROUND(AVG(LENGTH(CAST(e.data AS STRING))), 2) as avg_data_size_bytes,
    ROUND(SUM(LENGTH(CAST(e.data AS STRING))) / 1024.0 / 1024.0, 2) as total_data_size_mb
FROM execution_entity e
INNER JOIN workflow_entity w ON e.workflowId = w.id
WHERE e.startedAt >= NOW() - INTERVAL 30 DAYS
GROUP BY w.id, w.name
ORDER BY total_data_size_mb DESC
LIMIT 10;

-- 14. DAILY SUCCESS RATE TREND
-- Track reliability over time
SELECT 
    DATE(startedAt) as date,
    COUNT(*) as total,
    SUM(CASE WHEN finished = true THEN 1 ELSE 0 END) as successful,
    ROUND(100.0 * SUM(CASE WHEN finished = true THEN 1 ELSE 0 END) / COUNT(*), 2) as success_rate
FROM execution_entity
WHERE startedAt >= NOW() - INTERVAL 30 DAYS
GROUP BY DATE(startedAt)
ORDER BY date DESC;

-- 15. WORKFLOW EXECUTION FREQUENCY
-- Identify execution patterns
SELECT 
    w.name,
    COUNT(e.id) as total_executions,
    ROUND(CAST(COUNT(e.id) AS DOUBLE) / 30, 2) as avg_executions_per_day,
    MIN(e.startedAt) as first_execution,
    MAX(e.startedAt) as last_execution
FROM workflow_entity w
INNER JOIN execution_entity e ON e.workflowId = w.id
WHERE e.startedAt >= NOW() - INTERVAL 30 DAYS
GROUP BY w.id, w.name
ORDER BY avg_executions_per_day DESC;


-- ============================================
-- ADDITIONAL WORKFLOW ANALYSIS QUERIES
-- ============================================

-- 16. WORKFLOWS BY NODE COUNT
-- Distribution of workflows by complexity (number of nodes)
SELECT 
    w.id,
    w.name,
    w.active,
    SIZE(FROM_JSON(w.nodes, 'array<struct<id:string>>')) as node_count,
    w.createdAt,
    w.updatedAt
FROM workflow_entity w
ORDER BY node_count DESC;

-- 17. WORKFLOW COMPLEXITY DISTRIBUTION
-- Group workflows by node count ranges
SELECT 
    CASE 
        WHEN node_count = 0 THEN '0 nodes (empty)'
        WHEN node_count BETWEEN 1 AND 5 THEN '1-5 nodes (simple)'
        WHEN node_count BETWEEN 6 AND 10 THEN '6-10 nodes (moderate)'
        WHEN node_count BETWEEN 11 AND 20 THEN '11-20 nodes (complex)'
        ELSE '20+ nodes (very complex)'
    END as complexity_level,
    COUNT(*) as workflow_count,
    ROUND(AVG(node_count), 2) as avg_nodes_in_range
FROM (
    SELECT 
        w.id,
        SIZE(FROM_JSON(w.nodes, 'array<struct<id:string>>')) as node_count
    FROM workflow_entity w
) subquery
GROUP BY 
    CASE 
        WHEN node_count = 0 THEN '0 nodes (empty)'
        WHEN node_count BETWEEN 1 AND 5 THEN '1-5 nodes (simple)'
        WHEN node_count BETWEEN 6 AND 10 THEN '6-10 nodes (moderate)'
        WHEN node_count BETWEEN 11 AND 20 THEN '11-20 nodes (complex)'
        ELSE '20+ nodes (very complex)'
    END
ORDER BY avg_nodes_in_range;

-- 18. MOST USED NODE TYPES
-- Identify which node types are most popular across workflows
SELECT 
    node_type,
    COUNT(*) as usage_count,
    COUNT(DISTINCT workflow_id) as workflows_using
FROM (
    SELECT 
        w.id as workflow_id,
        EXPLODE(FROM_JSON(w.nodes, 'array<struct<type:string>>')) as node_data
    FROM workflow_entity w
) exploded
LATERAL VIEW OUTER EXPLODE(ARRAY(node_data.type)) AS node_type
WHERE node_type IS NOT NULL
GROUP BY node_type
ORDER BY usage_count DESC
LIMIT 20;

-- 19. WORKFLOWS WITH MOST CONNECTIONS
-- Analyze workflow complexity by connection count
SELECT 
    w.id,
    w.name,
    w.active,
    SIZE(FROM_JSON(w.connections, 'map<string,map<string,array<struct<node:string>>>>')) as connection_count,
    SIZE(FROM_JSON(w.nodes, 'array<struct<id:string>>')) as node_count,
    w.updatedAt
FROM workflow_entity w
ORDER BY connection_count DESC
LIMIT 20;

-- 20. AVERAGE NODES PER WORKFLOW BY STATUS
-- Compare complexity between active and inactive workflows
SELECT 
    w.active,
    COUNT(*) as workflow_count,
    ROUND(AVG(SIZE(FROM_JSON(w.nodes, 'array<struct<id:string>>')))), 2) as avg_node_count,
    MIN(SIZE(FROM_JSON(w.nodes, 'array<struct<id:string>>'))) as min_nodes,
    MAX(SIZE(FROM_JSON(w.nodes, 'array<struct<id:string>>'))) as max_nodes
FROM workflow_entity w
GROUP BY w.active;

-- 21. WORKFLOW EXECUTION SUCCESS BY COMPLEXITY
-- Correlation between workflow complexity and success rate
SELECT 
    CASE 
        WHEN node_count BETWEEN 1 AND 5 THEN '1-5 nodes'
        WHEN node_count BETWEEN 6 AND 10 THEN '6-10 nodes'
        WHEN node_count BETWEEN 11 AND 20 THEN '11-20 nodes'
        ELSE '20+ nodes'
    END as complexity_level,
    COUNT(DISTINCT w.id) as workflow_count,
    COUNT(e.id) as total_executions,
    SUM(CASE WHEN e.finished = true THEN 1 ELSE 0 END) as successful_executions,
    ROUND(100.0 * SUM(CASE WHEN e.finished = true THEN 1 ELSE 0 END) / COUNT(e.id), 2) as success_rate_percent
FROM (
    SELECT 
        id,
        SIZE(FROM_JSON(nodes, 'array<struct<id:string>>')) as node_count
    FROM workflow_entity
) w
LEFT JOIN execution_entity e ON e.workflowId = w.id
WHERE e.startedAt >= NOW() - INTERVAL 30 DAYS
GROUP BY 
    CASE 
        WHEN node_count BETWEEN 1 AND 5 THEN '1-5 nodes'
        WHEN node_count BETWEEN 6 AND 10 THEN '6-10 nodes'
        WHEN node_count BETWEEN 11 AND 20 THEN '11-20 nodes'
        ELSE '20+ nodes'
    END
ORDER BY workflow_count DESC;

-- 22. WORKFLOWS WITH SPECIFIC NODE TYPES
-- Find workflows using specific integrations (e.g., HTTP Request, Webhook)
SELECT 
    w.id,
    w.name,
    w.active,
    node_type,
    COUNT(*) as node_type_count
FROM workflow_entity w
LATERAL VIEW EXPLODE(FROM_JSON(w.nodes, 'array<struct<type:string>>')) AS node_data
WHERE node_data.type IN ('n8n-nodes-base.httpRequest', 'n8n-nodes-base.webhook', 'n8n-nodes-base.code')
GROUP BY w.id, w.name, w.active, node_data.type
ORDER BY w.name, node_type;

-- 23. WORKFLOW CREATION TRENDS
-- Track when workflows were created over time
SELECT 
    DATE_TRUNC('month', createdAt) as creation_month,
    COUNT(*) as workflows_created,
    SUM(CASE WHEN active = true THEN 1 ELSE 0 END) as currently_active
FROM workflow_entity
GROUP BY DATE_TRUNC('month', createdAt)
ORDER BY creation_month DESC;

-- 24. WORKFLOW UPDATE FREQUENCY
-- Identify workflows that are frequently modified
SELECT 
    w.id,
    w.name,
    w.active,
    w.createdAt,
    w.updatedAt,
    DATEDIFF(DAY, w.createdAt, w.updatedAt) as days_since_creation,
    COUNT(e.id) as execution_count_last_30_days
FROM workflow_entity w
LEFT JOIN execution_entity e ON e.workflowId = w.id 
    AND e.startedAt >= NOW() - INTERVAL 30 DAYS
WHERE w.updatedAt > w.createdAt
GROUP BY w.id, w.name, w.active, w.createdAt, w.updatedAt
ORDER BY w.updatedAt DESC
LIMIT 20;

-- 25. EMPTY OR UNUSED WORKFLOWS
-- Find workflows with no nodes or no executions
SELECT 
    w.id,
    w.name,
    w.active,
    SIZE(FROM_JSON(w.nodes, 'array<struct<id:string>>')) as node_count,
    COUNT(e.id) as execution_count,
    MAX(e.startedAt) as last_execution,
    w.createdAt,
    w.updatedAt
FROM workflow_entity w
LEFT JOIN execution_entity e ON e.workflowId = w.id
GROUP BY w.id, w.name, w.active, w.nodes, w.createdAt, w.updatedAt
HAVING SIZE(FROM_JSON(w.nodes, 'array<struct<id:string>>')) = 0 
    OR COUNT(e.id) = 0
ORDER BY w.updatedAt DESC;

-- 26. WORKFLOW SETTINGS ANALYSIS
-- Analyze workflow configuration settings
SELECT 
    w.id,
    w.name,
    w.active,
    FROM_JSON(w.settings, 'struct<saveDataErrorExecution:string,saveDataSuccessExecution:string,saveManualExecutions:boolean>').saveDataErrorExecution as save_error_data,
    FROM_JSON(w.settings, 'struct<saveDataErrorExecution:string,saveDataSuccessExecution:string,saveManualExecutions:boolean>').saveDataSuccessExecution as save_success_data,
    FROM_JSON(w.settings, 'struct<saveDataErrorExecution:string,saveDataSuccessExecution:string,saveManualExecutions:boolean>').saveManualExecutions as save_manual_executions
FROM workflow_entity w
WHERE w.settings IS NOT NULL
LIMIT 50;

-- 27. EXECUTION PERFORMANCE BY WORKFLOW SIZE
-- Average execution time grouped by workflow complexity
SELECT 
    CASE 
        WHEN node_count BETWEEN 1 AND 5 THEN '1-5 nodes'
        WHEN node_count BETWEEN 6 AND 10 THEN '6-10 nodes'
        WHEN node_count BETWEEN 11 AND 20 THEN '11-20 nodes'
        ELSE '20+ nodes'
    END as complexity_level,
    COUNT(e.id) as execution_count,
    ROUND(AVG(unix_seconds(e.stoppedAt) - unix_seconds(e.startedAt)), 2) as avg_duration_seconds,
    ROUND(MIN(unix_seconds(e.stoppedAt) - unix_seconds(e.startedAt)), 2) as min_duration_seconds,
    ROUND(MAX(unix_seconds(e.stoppedAt) - unix_seconds(e.startedAt)), 2) as max_duration_seconds
FROM (
    SELECT 
        id,
        SIZE(FROM_JSON(nodes, 'array<struct<id:string>>')) as node_count
    FROM workflow_entity
) w
INNER JOIN execution_entity e ON e.workflowId = w.id
WHERE e.startedAt >= NOW() - INTERVAL 30 DAYS
    AND e.stoppedAt IS NOT NULL
GROUP BY 
    CASE 
        WHEN node_count BETWEEN 1 AND 5 THEN '1-5 nodes'
        WHEN node_count BETWEEN 6 AND 10 THEN '6-10 nodes'
        WHEN node_count BETWEEN 11 AND 20 THEN '11-20 nodes'
        ELSE '20+ nodes'
    END
ORDER BY avg_duration_seconds DESC;
