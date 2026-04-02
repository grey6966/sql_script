SELECT 
    org_summary.片区,
    ROUND(org_summary.销售计划KL, 1) AS 销售计划KL,
    ROUND(org_summary.需求计划KL, 1) AS 需求计划KL,
    ROUND(org_summary.实际KL, 1) AS 实际KL,
    org_summary.销售计划执行,
    org_summary.需求计划执行,
    sku_summary.重点产品1,
    sku_summary.常规产品1,
    sku_summary.小计1,
    sku_summary.重点产品2,
    sku_summary.常规产品2,
    sku_summary.小计2,
    '80%' AS 目标准确率,
    CONCAT(CAST(ROUND(sku_summary.需求达成率数值 - 80, 1) AS STRING), '%') AS 与目标比差异
FROM (
    -- 组织维度按片区汇总
    SELECT 
        p.lvl1_org_name AS 片区,
        SUM(p.first_month_sales_litre) AS 销售计划KL,
        SUM(p.first_month_require_litre) AS 需求计划KL,
        SUM(s.op_sales_litre) AS 实际KL,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.first_month_sales_litre - COALESCE(s.op_sales_litre, 0))) / SUM(p.first_month_sales_litre))) * 100, 1) AS STRING), '%') AS 销售计划执行,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.first_month_require_litre - COALESCE(s.op_sales_litre, 0))) / SUM(p.first_month_require_litre))) * 100, 1) AS STRING), '%') AS 需求计划执行
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
        p.lvl1_org_name AS 片区,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品等级 = 1, ABS(p.销售计划 - COALESCE(s.实际销量, 0)), 0)) / SUM(IF(p.产品等级 = 1, p.销售计划, 0))) * 100, 1) AS STRING), '%') AS 重点产品1,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品等级 = 0, ABS(p.销售计划 - COALESCE(s.实际销量, 0)), 0)) / SUM(IF(p.产品等级 = 0, p.销售计划, 0))) * 100, 1) AS STRING), '%') AS 常规产品1,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.销售计划 - COALESCE(s.实际销量, 0))) / SUM(p.销售计划)) * 100, 1) AS STRING), '%') AS 小计1,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品等级 = 1, ABS(p.需求计划 - COALESCE(s.实际销量, 0)), 0)) / SUM(IF(p.产品等级 = 1, p.需求计划, 0))) * 100, 1) AS STRING), '%') AS 重点产品2,
        CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品等级 = 0, ABS(p.需求计划 - COALESCE(s.实际销量, 0)), 0)) / SUM(IF(p.产品等级 = 0, p.需求计划, 0))) * 100, 1) AS STRING), '%') AS 常规产品2,
        CONCAT(CAST(ROUND((1 - (SUM(ABS(p.需求计划 - COALESCE(s.实际销量, 0))) / SUM(p.需求计划)) * 100, 1) AS STRING), '%') AS 小计2,
        ROUND((1 - (SUM(ABS(p.需求计划 - COALESCE(s.实际销量, 0))) / SUM(p.需求计划)) * 100, 1) AS 需求达成率数值
    FROM (
        -- SKU维度计划数据
        SELECT 
            lvl1_org_name,
            product_code,
            IF(op_second_brand_name = '重点高端', 1, 0) AS 产品等级,
            SUM(first_month_sales_litre) AS 销售计划,
            SUM(first_month_require_litre) AS 需求计划
        FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
        WHERE report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE('2025-04-01', '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
        GROUP BY lvl1_org_name, product_code, IF(op_second_brand_name = '重点高端', 1, 0)
    ) p
    LEFT JOIN (
        -- SKU维度销售实绩
        SELECT 
            oc_lvl1_org_name,
            product_code,
            IF(op_second_important_brand_name = '重点高端', 1, 0) AS 产品等级,
            SUM(op_sales_litre) AS 实际销量
        FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
        WHERE date_unit = '月'
          AND line_bill_created_date = '2025-04-01'
        GROUP BY oc_lvl1_org_name, product_code, IF(op_second_important_brand_name = '重点高端', 1, 0)
    ) s ON p.lvl1_org_name = s.oc_lvl1_org_name 
       AND p.product_code = s.product_code 
       AND p.产品等级 = s.产品等级
    GROUP BY p.lvl1_org_name
) sku_summary ON org_summary.片区 = sku_summary.片区
ORDER BY org_summary.片区
