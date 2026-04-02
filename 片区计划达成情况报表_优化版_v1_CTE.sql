WITH 
-- 配置参数
params AS (
    SELECT 
        '2025-04' AS report_month,
        '2025-04-01' AS sales_date
),

-- 组织维度计划数据
org_plan AS (
    SELECT 
        lvl1_org_name AS 片区,
        lvl2_org_name AS 二级片区,
        SUM(first_month_sales_litre) AS 销售计划,
        SUM(first_month_require_litre) AS 需求计划
    FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
    CROSS JOIN params
    WHERE report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(params.report_month, '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
    GROUP BY lvl1_org_name, lvl2_org_name
),

-- 组织维度销售实绩
org_sales AS (
    SELECT 
        oc_lvl1_org_name AS 片区,
        oc_lvl2_org_name AS 二级片区,
        SUM(op_sales_litre) AS 实际销量
    FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
    CROSS JOIN params
    WHERE date_unit = '月'
      AND line_bill_created_date = params.sales_date
    GROUP BY oc_lvl1_org_name, oc_lvl2_org_name
),

-- SKU维度计划数据
sku_plan AS (
    SELECT 
        lvl1_org_name AS 片区,
        product_code AS 产品编码,
        IF(op_second_brand_name = '重点高端', 1, 0) AS 产品等级,
        SUM(first_month_sales_litre) AS 销售计划,
        SUM(first_month_require_litre) AS 需求计划
    FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
    CROSS JOIN params
    WHERE report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(params.report_month, '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
    GROUP BY lvl1_org_name, product_code, IF(op_second_brand_name = '重点高端', 1, 0)
),

-- SKU维度销售实绩
sku_sales AS (
    SELECT 
        oc_lvl1_org_name AS 片区,
        product_code AS 产品编码,
        IF(op_second_important_brand_name = '重点高端', 1, 0) AS 产品等级,
        SUM(op_sales_litre) AS 实际销量
    FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
    CROSS JOIN params
    WHERE date_unit = '月'
      AND line_bill_created_date = params.sales_date
    GROUP BY oc_lvl1_org_name, product_code, IF(op_second_important_brand_name = '重点高端', 1, 0)
),

-- 组织维度合并后按片区汇总
org_merged AS (
    SELECT 
        p.片区,
        SUM(p.销售计划) AS 销售计划KL,
        SUM(p.需求计划) AS 需求计划KL,
        SUM(s.实际销量) AS 实际KL,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.销售计划 - COALESCE(s.实际销量, 0))) / SUM(p.销售计划))) * 100, 1) AS STRING), '%') AS 销售计划执行,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.需求计划 - COALESCE(s.实际销量, 0))) / SUM(p.需求计划))) * 100, 1) AS STRING), '%') AS 需求计划执行
    FROM org_plan p
    LEFT JOIN org_sales s 
        ON p.片区 = s.片区 
       AND p.二级片区 = s.二级片区
    GROUP BY p.片区
),

-- SKU维度合并后按片区汇总
sku_merged AS (
    SELECT 
        p.片区,
        -- 销售计划达成率 - 重点产品
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品等级 = 1, ABS(p.销售计划 - COALESCE(s.实际销量, 0)), 0)) / SUM(IF(p.产品等级 = 1, p.销售计划, 0))) * 100, 1) AS STRING), '%') AS 重点产品1,
        -- 销售计划达成率 - 常规产品
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品等级 = 0, ABS(p.销售计划 - COALESCE(s.实际销量, 0)), 0)) / SUM(IF(p.产品等级 = 0, p.销售计划, 0))) * 100, 1) AS STRING), '%') AS 常规产品1,
        -- 销售计划达成率 - 小计
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.销售计划 - COALESCE(s.实际销量, 0))) / SUM(p.销售计划)) * 100, 1) AS STRING), '%') AS 小计1,
        -- 需求计划达成率 - 重点产品
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品等级 = 1, ABS(p.需求计划 - COALESCE(s.实际销量, 0)), 0)) / SUM(IF(p.产品等级 = 1, p.需求计划, 0))) * 100, 1) AS STRING), '%') AS 重点产品2,
        -- 需求计划达成率 - 常规产品
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品等级 = 0, ABS(p.需求计划 - COALESCE(s.实际销量, 0)), 0)) / SUM(IF(p.产品等级 = 0, p.需求计划, 0))) * 100, 1) AS STRING), '%') AS 常规产品2,
        -- 需求计划达成率 - 小计
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.需求计划 - COALESCE(s.实际销量, 0))) / SUM(p.需求计划)) * 100, 1) AS STRING), '%') AS 小计2,
        -- 用于计算差异的数值型达成率
        ROUND((1 - (SUM(ABS(p.需求计划 - COALESCE(s.实际销量, 0))) / SUM(p.需求计划)) * 100, 1) AS 需求达成率数值
    FROM sku_plan p
    LEFT JOIN sku_sales s 
        ON p.片区 = s.片区 
       AND p.产品编码 = s.产品编码 
       AND p.产品等级 = s.产品等级
    GROUP BY p.片区
)

-- 最终结果
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
    CONCAT(CAST(ROUND(s.需求达成率数值 - 80, 1) AS STRING), '%') AS 与目标比差异
FROM org_merged o
LEFT JOIN sku_merged s 
    ON o.片区 = s.片区
ORDER BY o.片区
