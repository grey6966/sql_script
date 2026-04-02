-- =============================================
-- 片区计划达成情况报表 - CTE优化版本
-- 优化目标：提升可读性，减少嵌套层数，结构清晰
-- =============================================

WITH
-- #############################################
-- 配置参数区 - 统一管理报表时间参数
-- #############################################
report_params AS (
    SELECT
        '2025-04' AS target_month,
        DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT('2025-04', '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m') AS plan_month,
        '2025-04-01' AS sales_date,
        80.0 AS target_accuracy_rate
),

-- #############################################
-- 数据层 - 组织维度计划数据
-- #############################################
org_plan_data AS (
    SELECT
        lvl1_org_name AS lv1,
        lvl2_org_name AS lv2,
        SUM(first_month_sales_litre) AS pl1,
        SUM(first_month_require_litre) AS pl2
    FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
    WHERE report_month = (SELECT plan_month FROM report_params)
    GROUP BY lvl1_org_name, lvl2_org_name
),

-- #############################################
-- 数据层 - 组织维度实际销售数据
-- #############################################
org_sales_data AS (
    SELECT
        oc_lvl1_org_name AS lv1,
        oc_lvl2_org_name AS lv2,
        SUM(op_sales_litre) AS sl
    FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
    WHERE date_unit = '月'
      AND line_bill_created_date = (SELECT sales_date FROM report_params)
    GROUP BY oc_lvl1_org_name, oc_lvl2_org_name
),

-- #############################################
-- 数据层 - SKU维度计划数据（按产品级别区分）
-- #############################################
sku_plan_data AS (
    SELECT
        lvl1_org_name AS lv1,
        product_code AS sku,
        IF(op_second_brand_name = '重点高端', 1, 0) AS lev,
        SUM(first_month_sales_litre) AS pl1,
        SUM(first_month_require_litre) AS pl2
    FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
    WHERE report_month = (SELECT plan_month FROM report_params)
    GROUP BY lvl1_org_name, product_code, IF(op_second_brand_name = '重点高端', 1, 0)
),

-- #############################################
-- 数据层 - SKU维度实际销售数据（按产品级别区分）
-- #############################################
sku_sales_data AS (
    SELECT
        oc_lvl1_org_name AS lv1,
        product_code AS sku,
        IF(op_second_important_brand_name = '重点高端', 1, 0) AS lev,
        SUM(op_sales_litre) AS sl
    FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
    WHERE date_unit = '月'
      AND line_bill_created_date = (SELECT sales_date FROM report_params)
    GROUP BY oc_lvl1_org_name, product_code, IF(op_second_important_brand_name = '重点高端', 1, 0)
),

-- #############################################
-- 聚合层 - 组织维度按片区汇总
-- #############################################
org_summary AS (
    SELECT
        lv1,
        SUM(pl1) AS pl1,
        SUM(pl2) AS pl2,
        SUM(sl) AS sl,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(pl1 - sl)) / SUM(pl1))) * 100, 1) AS STRING), '%') AS pl1_org_r,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(pl2 - sl)) / SUM(pl2))) * 100, 1) AS STRING), '%') AS pl2_org_r
    FROM (
        SELECT
            T1.lv1,
            T1.lv2,
            T1.pl1,
            T1.pl2,
            T2.sl
        FROM org_plan_data T1
        LEFT JOIN org_sales_data T2
            ON T1.lv1 = T2.lv1
            AND T1.lv2 = T2.lv2
    ) V1
    GROUP BY lv1
),

-- #############################################
-- 聚合层 - SKU维度按片区汇总
-- #############################################
sku_summary AS (
    SELECT
        lv1,
        CONCAT(CAST(ROUND((1 - (SUM(IF(lev = 1, ABS(pl1 - sl), 0)) / SUM(IF(lev = 1, pl1, 0)))) * 100, 1) AS STRING), '%') AS pl1_lev1_sku_r,
        CONCAT(CAST(ROUND((1 - (SUM(IF(lev = 0, ABS(pl1 - sl), 0)) / SUM(IF(lev = 0, pl1, 0)))) * 100, 1) AS STRING), '%') AS pl1_lev0_sku_r,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(pl1 - sl)) / SUM(pl1))) * 100, 1) AS STRING), '%') AS pl1_sku_r,
        CONCAT(CAST(ROUND((1 - (SUM(IF(lev = 1, ABS(pl2 - sl), 0)) / SUM(IF(lev = 1, pl2, 0)))) * 100, 1) AS STRING), '%') AS pl2_lev1_sku_r,
        CONCAT(CAST(ROUND((1 - (SUM(IF(lev = 0, ABS(pl2 - sl), 0)) / SUM(IF(lev = 0, pl2, 0)))) * 100, 1) AS STRING), '%') AS pl2_lev0_sku_r,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(pl2 - sl)) / SUM(pl2))) * 100, 1) AS STRING), '%') AS pl2_sku_r,
        ROUND((1 - (SUM(ABS(pl2 - sl)) / SUM(pl2))) * 100, 1) AS pl2_sku_num
    FROM (
        SELECT
            T1.lv1,
            T1.sku,
            T1.lev,
            T1.pl1,
            T1.pl2,
            T2.sl
        FROM sku_plan_data T1
        LEFT JOIN sku_sales_data T2
            ON T1.lv1 = T2.lv1
            AND T1.sku = T2.sku
            AND T1.lev = T2.lev
    ) V2
    GROUP BY lv1
)

-- #############################################
-- 最终输出层
-- #############################################
SELECT
    O.lv1 AS 片区,
    ROUND(O.pl1, 1) AS 销售计划KL,
    ROUND(O.pl2, 1) AS 需求计划KL,
    ROUND(O.sl, 1) AS 实际KL,
    O.pl1_org_r AS 销售计划执行,
    O.pl2_org_r AS 需求计划执行,
    S.pl1_lev1_sku_r AS 重点产品1,
    S.pl1_lev0_sku_r AS 常规产品1,
    S.pl1_sku_r AS 小计1,
    S.pl2_lev1_sku_r AS 重点产品2,
    S.pl2_lev0_sku_r AS 常规产品2,
    S.pl2_sku_r AS 小计2,
    '80%' AS 目标准确率,
    CONCAT(CAST(ROUND(S.pl2_sku_num - 80, 1) AS STRING), '%') AS 与目标比差异
FROM org_summary O
LEFT JOIN sku_summary S
    ON O.lv1 = S.lv1
ORDER BY O.lv1;
