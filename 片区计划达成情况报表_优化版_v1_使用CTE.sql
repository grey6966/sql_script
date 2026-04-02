WITH 
-- 参数定义：统一管理报表月份
report_params AS (
    SELECT 
        '2025-04' AS target_month,
        DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT('2025-04', '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m') AS plan_report_month
),

-- 计划基础数据：按组织维度聚合
plan_org_data AS (
    SELECT 
        lvl1_org_name AS 片区,
        lvl2_org_name AS 二级片区,
        SUM(first_month_sales_litre) AS 销售计划KL,
        SUM(first_month_require_litre) AS 需求计划KL
    FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf p
    CROSS JOIN report_params rp
    WHERE report_month = rp.plan_report_month
    GROUP BY lvl1_org_name, lvl2_org_name
),

-- 实际销售基础数据：按组织维度聚合
sales_org_data AS (
    SELECT 
        oc_lvl1_org_name AS 片区,
        oc_lvl2_org_name AS 二级片区,
        SUM(op_sales_litre) AS 实际KL
    FROM crb_edw_dws_op.dws_op_sales_bill_agg_df s
    CROSS JOIN report_params rp
    WHERE date_unit = '月'
      AND line_bill_created_date = CONCAT(rp.target_month, '-01')
    GROUP BY oc_lvl1_org_name, oc_lvl2_org_name
),

-- 组织维度聚合计算：计算执行率指标
org_agg_metrics AS (
    SELECT 
        p.片区,
        SUM(p.销售计划KL) AS 销售计划KL,
        SUM(p.需求计划KL) AS 需求计划KL,
        SUM(s.实际KL) AS 实际KL,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.销售计划KL - s.实际KL)) / SUM(p.销售计划KL))) * 100, 1) AS STRING), '%') AS 销售计划执行,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.需求计划KL - s.实际KL)) / SUM(p.需求计划KL))) * 100, 1) AS STRING), '%') AS 需求计划执行
    FROM plan_org_data p
    LEFT JOIN sales_org_data s 
        ON p.片区 = s.片区 
       AND p.二级片区 = s.二级片区
    GROUP BY p.片区
),

-- 计划基础数据：按SKU维度聚合
plan_sku_data AS (
    SELECT 
        lvl1_org_name AS 片区,
        product_code AS SKU编码,
        IF(op_second_brand_name = '重点高端', 1, 0) AS 产品层级标记,
        SUM(first_month_sales_litre) AS 销售计划KL,
        SUM(first_month_require_litre) AS 需求计划KL
    FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf p
    CROSS JOIN report_params rp
    WHERE report_month = rp.plan_report_month
    GROUP BY lvl1_org_name, product_code, IF(op_second_brand_name = '重点高端', 1, 0)
),

-- 实际销售基础数据：按SKU维度聚合
sales_sku_data AS (
    SELECT 
        oc_lvl1_org_name AS 片区,
        product_code AS SKU编码,
        IF(op_second_important_brand_name = '重点高端', 1, 0) AS 产品层级标记,
        SUM(op_sales_litre) AS 实际KL
    FROM crb_edw_dws_op.dws_op_sales_bill_agg_df s
    CROSS JOIN report_params rp
    WHERE date_unit = '月'
      AND line_bill_created_date = CONCAT(rp.target_month, '-01')
    GROUP BY oc_lvl1_org_name, product_code, IF(op_second_important_brand_name = '重点高端', 1, 0)
),

-- SKU维度聚合计算：分产品层级计算执行率
sku_agg_metrics AS (
    SELECT 
        p.片区,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品层级标记 = 1, ABS(p.销售计划KL - s.实际KL), 0)) / SUM(IF(p.产品层级标记 = 1, p.销售计划KL, 0)))) * 100, 1) AS STRING), '%') AS 重点产品1,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品层级标记 = 0, ABS(p.销售计划KL - s.实际KL), 0)) / SUM(IF(p.产品层级标记 = 0, p.销售计划KL, 0)))) * 100, 1) AS STRING), '%') AS 常规产品1,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.销售计划KL - s.实际KL)) / SUM(p.销售计划KL))) * 100, 1) AS STRING), '%') AS 小计1,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品层级标记 = 1, ABS(p.需求计划KL - s.实际KL), 0)) / SUM(IF(p.产品层级标记 = 1, p.需求计划KL, 0)))) * 100, 1) AS STRING), '%') AS 重点产品2,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品层级标记 = 0, ABS(p.需求计划KL - s.实际KL), 0)) / SUM(IF(p.产品层级标记 = 0, p.需求计划KL, 0)))) * 100, 1) AS STRING), '%') AS 常规产品2,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.需求计划KL - s.实际KL)) / SUM(p.需求计划KL))) * 100, 1) AS STRING), '%') AS 小计2,
        ROUND((1 - (SUM(ABS(p.需求计划KL - s.实际KL)) / SUM(p.需求计划KL))) * 100, 1) AS 小计2数值
    FROM plan_sku_data p
    LEFT JOIN sales_sku_data s 
        ON p.片区 = s.片区 
       AND p.SKU编码 = s.SKU编码 
       AND p.产品层级标记 = s.产品层级标记
    GROUP BY p.片区
)

-- 最终结果输出
SELECT 
    org.片区,
    ROUND(org.销售计划KL, 1) AS 销售计划KL,
    ROUND(org.需求计划KL, 1) AS 需求计划KL,
    ROUND(org.实际KL, 1) AS 实际KL,
    org.销售计划执行,
    org.需求计划执行,
    sku.重点产品1,
    sku.常规产品1,
    sku.小计1,
    sku.重点产品2,
    sku.常规产品2,
    sku.小计2,
    '80%' AS 目标准确率,
    CONCAT(CAST(ROUND(sku.小计2数值 - 80, 1) AS STRING), '%') AS 与目标比差异
FROM org_agg_metrics org
LEFT JOIN sku_agg_metrics sku 
    ON org.片区 = sku.片区
ORDER BY org.片区;
