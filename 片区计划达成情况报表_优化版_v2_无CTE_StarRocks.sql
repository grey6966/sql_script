SELECT 
    org_summary.lv1 AS 片区,
    ROUND(org_summary.pl1, 1) AS 销售计划KL,
    ROUND(org_summary.pl2, 1) AS 需求计划KL,
    ROUND(org_summary.sl, 1) AS 实际KL,
    CONCAT(CAST(org_summary.pl1_org_num AS VARCHAR), '%') AS 销售计划执行,
    CONCAT(CAST(org_summary.pl2_org_num AS VARCHAR), '%') AS 需求计划执行,
    CONCAT(CAST(sku_summary.pl1_lev1_sku_num AS VARCHAR), '%') AS 重点产品1,
    CONCAT(CAST(sku_summary.pl1_lev0_sku_num AS VARCHAR), '%') AS 常规产品1,
    CONCAT(CAST(sku_summary.pl1_sku_num AS VARCHAR), '%') AS 小计1,
    CONCAT(CAST(sku_summary.pl2_lev1_sku_num AS VARCHAR), '%') AS 重点产品2,
    CONCAT(CAST(sku_summary.pl2_lev0_sku_num AS VARCHAR), '%') AS 常规产品2,
    CONCAT(CAST(sku_summary.pl2_sku_num AS VARCHAR), '%') AS 小计2,
    '80%' AS 目标准确率,
    CONCAT(CAST(ROUND(sku_summary.pl2_sku_num - 80, 1) AS VARCHAR), '%') AS 与目标比差异
FROM (
    -- 组织维度按片区汇总
    SELECT 
        p.lvl1_org_name AS lv1,
        SUM(p.first_month_sales_litre) AS pl1,
        SUM(p.first_month_require_litre) AS pl2,
        SUM(s.op_sales_litre) AS sl,
        ROUND((1 - (SUM(ABS(p.first_month_sales_litre - s.op_sales_litre)) / SUM(p.first_month_sales_litre))) * 100, 1) AS pl1_org_num,
        ROUND((1 - (SUM(ABS(p.first_month_require_litre - s.op_sales_litre)) / SUM(p.first_month_require_litre))) * 100, 1) AS pl2_org_num
    FROM (
        -- 组织维度计划数据
        SELECT 
            lvl1_org_name,
            lvl2_org_name,
            SUM(first_month_sales_litre) AS first_month_sales_litre,
            SUM(first_month_require_litre) AS first_month_require_litre
        FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
        WHERE report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE('2025-04-01', '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
        GROUP BY lvl1_org_name, lvl2_org_name
    ) p
    LEFT JOIN (
        -- 组织维度销售实绩
        SELECT 
            oc_lvl1_org_name,
            oc_lvl2_org_name,
            SUM(op_sales_litre) AS op_sales_litre
        FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
        WHERE date_unit = '月'
          AND line_bill_created_date = '2025-04-01'
        GROUP BY oc_lvl1_org_name, oc_lvl2_org_name
    ) s ON p.lvl1_org_name = s.oc_lvl1_org_name 
       AND p.lvl2_org_name = s.oc_lvl2_org_name
    GROUP BY p.lvl1_org_name
) org_summary
LEFT JOIN (
    -- SKU维度按片区汇总
    SELECT 
        p.lvl1_org_name AS lv1,
        ROUND((1 - (SUM(IF(p.lev = 1, ABS(p.pl1 - s.sl), 0)) / SUM(IF(p.lev = 1, p.pl1, 0))) * 100, 1) AS pl1_lev1_sku_num,
        ROUND((1 - (SUM(IF(p.lev = 0, ABS(p.pl1 - s.sl), 0)) / SUM(IF(p.lev = 0, p.pl1, 0))) * 100, 1) AS pl1_lev0_sku_num,
        ROUND((1 - (SUM(ABS(p.pl1 - s.sl)) / SUM(p.pl1))) * 100, 1) AS pl1_sku_num,
        ROUND((1 - (SUM(IF(p.lev = 1, ABS(p.pl2 - s.sl), 0)) / SUM(IF(p.lev = 1, p.pl2, 0))) * 100, 1) AS pl2_lev1_sku_num,
        ROUND((1 - (SUM(IF(p.lev = 0, ABS(p.pl2 - s.sl), 0)) / SUM(IF(p.lev = 0, p.pl2, 0))) * 100, 1) AS pl2_lev0_sku_num,
        ROUND((1 - (SUM(ABS(p.pl2 - s.sl)) / SUM(p.pl2))) * 100, 1) AS pl2_sku_num
    FROM (
        -- SKU维度计划数据
        SELECT 
            lvl1_org_name,
            product_code,
            IF(op_second_brand_name = '重点高端', 1, 0) AS lev,
            SUM(first_month_sales_litre) AS pl1,
            SUM(first_month_require_litre) AS pl2
        FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
        WHERE report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE('2025-04-01', '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
        GROUP BY lvl1_org_name, product_code, IF(op_second_brand_name = '重点高端', 1, 0)
    ) p
    LEFT JOIN (
        -- SKU维度销售实绩
        SELECT 
            oc_lvl1_org_name,
            product_code,
            IF(op_second_important_brand_name = '重点高端', 1, 0) AS lev,
            SUM(op_sales_litre) AS sl
        FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
        WHERE date_unit = '月'
          AND line_bill_created_date = '2025-04-01'
        GROUP BY oc_lvl1_org_name, product_code, IF(op_second_important_brand_name = '重点高端', 1, 0)
    ) s ON p.lvl1_org_name = s.oc_lvl1_org_name 
       AND p.product_code = s.product_code 
       AND p.lev = s.lev
    GROUP BY p.lvl1_org_name
) sku_summary ON org_summary.lv1 = sku_summary.lv1
ORDER BY org_summary.lv1
