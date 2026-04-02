WITH 
-- 1. 计划数据（组织维度）
plan_org_data AS (
    SELECT 
        lvl1_org_name AS lv1,
        lvl2_org_name AS lv2,
        SUM(first_month_sales_litre) AS pl1,
        SUM(first_month_require_litre) AS pl2
    FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf 
    WHERE report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT('2025-04', '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
    GROUP BY lvl1_org_name, lvl2_org_name
),

-- 2. 实际销售数据（组织维度）
sales_org_data AS (
    SELECT 
        oc_lvl1_org_name AS lv1,
        oc_lvl2_org_name AS lv2,
        SUM(op_sales_litre) AS sl
    FROM crb_edw_dws_op.dws_op_sales_bill_agg_df  
    WHERE date_unit = '月'
      AND line_bill_created_date = '2025-04-01'
    GROUP BY oc_lvl1_org_name, oc_lvl2_org_name
),

-- 3. 计划与销售合并（组织维度）
org_merged AS (
    SELECT 
        T1.lv1,
        T1.lv2,
        T1.pl1,
        T1.pl2,
        T2.sl
    FROM plan_org_data T1
    LEFT JOIN sales_org_data T2 
        ON T1.lv1 = T2.lv1 
        AND T1.lv2 = T2.lv2
),

-- 4. 组织维度聚合结果
org_agg AS (
    SELECT 
        lv1,
        SUM(pl1) AS pl1,
        SUM(pl2) AS pl2,
        SUM(sl) AS sl,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(pl1 - sl)) / SUM(pl1))) * 100, 1) AS STRING), '%') AS pl1_org_r,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(pl2 - sl)) / SUM(pl2))) * 100, 1) AS STRING), '%') AS pl2_org_r
    FROM org_merged
    GROUP BY lv1
),

-- 5. 计划数据（SKU维度）
plan_sku_data AS (
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

-- 6. 实际销售数据（SKU维度）
sales_sku_data AS (
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

-- 7. 计划与销售合并（SKU维度）
sku_merged AS (
    SELECT 
        T1.lv1,
        T1.sku,
        T1.lev,
        T1.pl1,
        T1.pl2,
        T2.sl
    FROM plan_sku_data T1
    LEFT JOIN sales_sku_data T2 
        ON T1.lv1 = T2.lv1 
        AND T1.sku = T2.sku 
        AND T1.lev = T2.lev
),

-- 8. SKU维度聚合结果
sku_agg AS (
    SELECT 
        lv1,
        CONCAT(CAST(ROUND((1 - (SUM(IF(lev = 1, ABS(pl1 - sl), 0)) / SUM(IF(lev = 1, pl1, 0)))) * 100, 1) AS STRING), '%') AS pl1_lev1_sku_r,
        CONCAT(CAST(ROUND((1 - (SUM(IF(lev = 0, ABS(pl1 - sl), 0)) / SUM(IF(lev = 0, pl1, 0)))) * 100, 1) AS STRING), '%') AS pl1_lev0_sku_r,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(pl1 - sl)) / SUM(pl1))) * 100, 1) AS STRING), '%') AS pl1_sku_r,
        CONCAT(CAST(ROUND((1 - (SUM(IF(lev = 1, ABS(pl2 - sl), 0)) / SUM(IF(lev = 1, pl2, 0)))) * 100, 1) AS STRING), '%') AS pl2_lev1_sku_r,
        CONCAT(CAST(ROUND((1 - (SUM(IF(lev = 0, ABS(pl2 - sl), 0)) / SUM(IF(lev = 0, pl2, 0)))) * 100, 1) AS STRING), '%') AS pl2_lev0_sku_r,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(pl2 - sl)) / SUM(pl2))) * 100, 1) AS STRING), '%') AS pl2_sku_r,
        ROUND((1 - (SUM(ABS(pl2 - sl)) / SUM(pl2))) * 100, 1) AS pl2_sku_num
    FROM sku_merged
    GROUP BY lv1
)

-- 最终查询：合并组织维度和SKU维度的结果
SELECT 
    VV1.lv1 AS 片区,
    ROUND(VV1.pl1, 1) AS 销售计划KL,
    ROUND(VV1.pl2, 1) AS 需求计划KL,
    ROUND(VV1.sl, 1) AS 实际KL,
    VV1.pl1_org_r AS 销售计划执行,
    VV1.pl2_org_r AS 需求计划执行,
    VV2.pl1_lev1_sku_r AS 重点产品1,
    VV2.pl1_lev0_sku_r AS 常规产品1,
    VV2.pl1_sku_r AS 小计1,
    VV2.pl2_lev1_sku_r AS 重点产品2,
    VV2.pl2_lev0_sku_r AS 常规产品2,
    VV2.pl2_sku_r AS 小计2,
    '80%' AS 目标准确率,
    CONCAT(CAST(ROUND(VV2.pl2_sku_num - 80, 1) AS STRING), '%') AS 与目标比差异
FROM org_agg VV1
LEFT JOIN sku_agg VV2 
    ON VV1.lv1 = VV2.lv1
ORDER BY VV1.lv1;
