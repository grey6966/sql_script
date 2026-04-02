WITH 
-- 参数定义：统一管理报表月份
report_params AS (
    SELECT 
        '2025-04' AS target_month,
        DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT('2025-04', '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m') AS plan_report_month,
        '2025-04-01' AS sales_bill_date
),

-- 计划基础数据：按片区+SKU+产品级别聚合
plan_sku_data AS (
    SELECT 
        lvl1_org_name AS 片区,
        product_code AS sku,
        IF(op_second_brand_name = '重点高端', 1, 0) AS 产品级别,
        SUM(first_month_sales_litre) AS 销售计划KL,
        SUM(first_month_require_litre) AS 需求计划KL
    FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
    CROSS JOIN report_params
    WHERE report_month = report_params.plan_report_month
    GROUP BY lvl1_org_name, product_code, IF(op_second_brand_name = '重点高端', 1, 0)
),

-- 计划聚合数据：按片区+二级组织聚合
plan_org_data AS (
    SELECT 
        lvl1_org_name AS 片区,
        lvl2_org_name AS 二级组织,
        SUM(first_month_sales_litre) AS 销售计划KL,
        SUM(first_month_require_litre) AS 需求计划KL
    FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
    CROSS JOIN report_params
    WHERE report_month = report_params.plan_report_month
    GROUP BY lvl1_org_name, lvl2_org_name
),

-- 销售基础数据：按片区+SKU+产品级别聚合
sales_sku_data AS (
    SELECT 
        oc_lvl1_org_name AS 片区,
        product_code AS sku,
        IF(op_second_important_brand_name = '重点高端', 1, 0) AS 产品级别,
        SUM(op_sales_litre) AS 实际KL
    FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
    CROSS JOIN report_params
    WHERE date_unit = '月' 
      AND line_bill_created_date = report_params.sales_bill_date
    GROUP BY oc_lvl1_org_name, product_code, IF(op_second_important_brand_name = '重点高端', 1, 0)
),

-- 销售聚合数据：按片区+二级组织聚合
sales_org_data AS (
    SELECT 
        oc_lvl1_org_name AS 片区,
        oc_lvl2_org_name AS 二级组织,
        SUM(op_sales_litre) AS 实际KL
    FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
    CROSS JOIN report_params
    WHERE date_unit = '月' 
      AND line_bill_created_date = report_params.sales_bill_date
    GROUP BY oc_lvl1_org_name, oc_lvl2_org_name
),

-- 组织维度达成率计算
org_achievement AS (
    SELECT 
        p.片区,
        SUM(p.销售计划KL) AS 销售计划KL,
        SUM(p.需求计划KL) AS 需求计划KL,
        SUM(s.实际KL) AS 实际KL,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.销售计划KL - COALESCE(s.实际KL, 0))) / SUM(p.销售计划KL))) * 100, 1) AS STRING), '%') AS 销售计划执行,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.需求计划KL - COALESCE(s.实际KL, 0))) / SUM(p.需求计划KL))) * 100, 1) AS STRING), '%') AS 需求计划执行
    FROM plan_org_data p
    LEFT JOIN sales_org_data s 
        ON p.片区 = s.片区 
       AND p.二级组织 = s.二级组织
    GROUP BY p.片区
),

-- SKU维度达成率计算
sku_achievement AS (
    SELECT 
        p.片区,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品级别 = 1, ABS(p.销售计划KL - COALESCE(s.实际KL, 0)), 0)) / SUM(IF(p.产品级别 = 1, p.销售计划KL, 0)))) * 100, 1) AS STRING), '%') AS 重点产品1,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品级别 = 0, ABS(p.销售计划KL - COALESCE(s.实际KL, 0)), 0)) / SUM(IF(p.产品级别 = 0, p.销售计划KL, 0)))) * 100, 1) AS STRING), '%') AS 常规产品1,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.销售计划KL - COALESCE(s.实际KL, 0))) / SUM(p.销售计划KL))) * 100, 1) AS STRING), '%') AS 小计1,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品级别 = 1, ABS(p.需求计划KL - COALESCE(s.实际KL, 0)), 0)) / SUM(IF(p.产品级别 = 1, p.需求计划KL, 0)))) * 100, 1) AS STRING), '%') AS 重点产品2,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品级别 = 0, ABS(p.需求计划KL - COALESCE(s.实际KL, 0)), 0)) / SUM(IF(p.产品级别 = 0, p.需求计划KL, 0)))) * 100, 1) AS STRING), '%') AS 常规产品2,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.需求计划KL - COALESCE(s.实际KL, 0))) / SUM(p.需求计划KL))) * 100, 1) AS STRING), '%') AS 小计2,
        ROUND((1 - (SUM(ABS(p.需求计划KL - COALESCE(s.实际KL, 0))) / SUM(p.需求计划KL))) * 100, 1) AS 小计2数值
    FROM plan_sku_data p
    LEFT JOIN sales_sku_data s 
        ON p.片区 = s.片区 
       AND p.sku = s.sku 
       AND p.产品级别 = s.产品级别
    GROUP BY p.片区
)

-- 最终结果输出
SELECT 
    o.片区,
    ROUND(o.销售计划KL, 1) AS 销售计划KL,
    ROUND(o.需求计划KL, 1) AS 需求计划KL,
    ROUND(o.实际KL, 1) AS 实际KL,
    o.销售计划执行,
    o.需求计划执行,
    s.重点产品1,
    s.常规产品1,
    s.小计1,
    s.重点产品2,
    s.常规产品2,
    s.小计2,
    '80%' AS 目标准确率,
    CONCAT(CAST(ROUND(s.小计2数值 - 80, 1) AS STRING), '%') AS 与目标比差异
FROM org_achievement o
LEFT JOIN sku_achievement s ON o.片区 = s.片区
ORDER BY o.片区;
