WITH 
-- 组织维度计划数据
org_plan AS (
    SELECT 
        lvl1_org_name AS lv1,
        lvl2_org_name AS lv2,
        SUM(first_month_sales_litre) AS pl1,
        SUM(first_month_require_litre) AS pl2
    FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
    WHERE report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT('2025-04', '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
    GROUP BY lvl1_org_name, lvl2_org_name
),

-- 组织维度销售实绩
org_sales AS (
    SELECT 
        oc_lvl1_org_name AS lv1,
        oc_lvl2_org_name AS lv2,
        SUM(op_sales_litre) AS sl
    FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
    WHERE date_unit = '月'
      AND line_bill_created_date = '2025-04-01'
    GROUP BY oc_lvl1_org_name, oc_lvl2_org_name
),

-- SKU维度计划数据
sku_plan AS (
    SELECT 
        lvl1_org_name AS lv1,
        product_code AS sku,
        IF(op_second_brand_name = '重点高端', 1, 0) AS lev,
        SUM(first_month_sales_litre) AS pl1,
        SUM(first_month_require_litre) AS pl2
    FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
    WHERE report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT('2025-04', '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
    GROUP BY lvl1_org_name, product_code, IF(op_second_brand_name = '重点高端', 1, 0)
),

-- SKU维度销售实绩
sku_sales AS (
    SELECT 
        oc_lvl1_org_name AS lv1,
        product_code AS sku,
        IF(op_second_important_brand_name = '重点高端', 1, 0) AS lev,
        SUM(op_sales_litre) AS sl
    FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
    WHERE date_unit = '月'
      AND line_bill_created_date = '2025-04-01'
    GROUP BY oc_lvl1_org_name, product_code, IF(op_second_important_brand_name = '重点高端', 1, 0)
),

-- 组织维度合并后按片区汇总
org_merged AS (
    SELECT 
        p.lv1,
        SUM(p.pl1) AS pl1,
        SUM(p.pl2) AS pl2,
        SUM(s.sl) AS sl,
        ROUND((1 - (SUM(ABS(p.pl1 - s.sl)) / SUM(p.pl1))) * 100, 1) AS pl1_org_num,
        ROUND((1 - (SUM(ABS(p.pl2 - s.sl)) / SUM(p.pl2))) * 100, 1) AS pl2_org_num
    FROM org_plan p
    LEFT JOIN org_sales s 
        ON p.lv1 = s.lv1 
       AND p.lv2 = s.lv2
    GROUP BY p.lv1
),

-- SKU维度合并后按片区汇总
sku_merged AS (
    SELECT 
        p.lv1,
        ROUND((1 - (SUM(IF(p.lev = 1, ABS(p.pl1 - s.sl), 0)) / SUM(IF(p.lev = 1, p.pl1, 0))) * 100, 1) AS pl1_lev1_sku_num,
        ROUND((1 - (SUM(IF(p.lev = 0, ABS(p.pl1 - s.sl), 0)) / SUM(IF(p.lev = 0, p.pl1, 0))) * 100, 1) AS pl1_lev0_sku_num,
        ROUND((1 - (SUM(ABS(p.pl1 - s.sl)) / SUM(p.pl1))) * 100, 1) AS pl1_sku_num,
        ROUND((1 - (SUM(IF(p.lev = 1, ABS(p.pl2 - s.sl), 0)) / SUM(IF(p.lev = 1, p.pl2, 0))) * 100, 1) AS pl2_lev1_sku_num,
        ROUND((1 - (SUM(IF(p.lev = 0, ABS(p.pl2 - s.sl), 0)) / SUM(IF(p.lev = 0, p.pl2, 0))) * 100, 1) AS pl2_lev0_sku_num,
        ROUND((1 - (SUM(ABS(p.pl2 - s.sl)) / SUM(p.pl2))) * 100, 1) AS pl2_sku_num
    FROM sku_plan p
    LEFT JOIN sku_sales s 
        ON p.lv1 = s.lv1 
       AND p.sku = s.sku 
       AND p.lev = s.lev
    GROUP BY p.lv1
)

-- 最终结果
SELECT 
    o.lv1 AS 片区,
    ROUND(o.pl1, 1) AS 销售计划KL,
    ROUND(o.pl2, 1) AS 需求计划KL,
    ROUND(o.sl, 1) AS 实际KL,
    CONCAT(CAST(o.pl1_org_num AS VARCHAR), '%') AS 销售计划执行,
    CONCAT(CAST(o.pl2_org_num AS VARCHAR), '%') AS 需求计划执行,
    CONCAT(CAST(s.pl1_lev1_sku_num AS VARCHAR), '%') AS 重点产品1,
    CONCAT(CAST(s.pl1_lev0_sku_num AS VARCHAR), '%') AS 常规产品1,
    CONCAT(CAST(s.pl1_sku_num AS VARCHAR), '%') AS 小计1,
    CONCAT(CAST(s.pl2_lev1_sku_num AS VARCHAR), '%') AS 重点产品2,
    CONCAT(CAST(s.pl2_lev0_sku_num AS VARCHAR), '%') AS 常规产品2,
    CONCAT(CAST(s.pl2_sku_num AS VARCHAR), '%') AS 小计2,
    '80%' AS 目标准确率,
    CONCAT(CAST(ROUND(s.pl2_sku_num - 80, 1) AS VARCHAR), '%') AS 与目标比差异
FROM org_merged o
LEFT JOIN sku_merged s 
    ON o.lv1 = s.lv1
ORDER BY o.lv1
