SELECT 
    org_metrics.片区,
    ROUND(org_metrics.销售计划KL, 1) AS 销售计划KL,
    ROUND(org_metrics.需求计划KL, 1) AS 需求计划KL,
    ROUND(org_metrics.实际KL, 1) AS 实际KL,
    org_metrics.销售计划执行,
    org_metrics.需求计划执行,
    sku_metrics.重点产品1,
    sku_metrics.常规产品1,
    sku_metrics.小计1,
    sku_metrics.重点产品2,
    sku_metrics.常规产品2,
    sku_metrics.小计2,
    '80%' AS 目标准确率,
    CONCAT(CAST(ROUND(sku_metrics.小计2数值 - 80, 1) AS STRING), '%') AS 与目标比差异
FROM 
    -- ==================================================
    -- 组织维度指标计算：按片区聚合计算执行率
    -- ==================================================
    (
        SELECT 
            p.片区,
            SUM(p.销售计划KL) AS 销售计划KL,
            SUM(p.需求计划KL) AS 需求计划KL,
            SUM(s.实际KL) AS 实际KL,
            CONCAT(CAST(ROUND((1 - (SUM(ABS(p.销售计划KL - s.实际KL)) / SUM(p.销售计划KL))) * 100, 1) AS STRING), '%') AS 销售计划执行,
            CONCAT(CAST(ROUND((1 - (SUM(ABS(p.需求计划KL - s.实际KL)) / SUM(p.需求计划KL))) * 100, 1) AS STRING), '%') AS 需求计划执行
        FROM 
            -- 计划基础数据（组织维度）
            (
                SELECT 
                    lvl1_org_name AS 片区,
                    lvl2_org_name AS 二级片区,
                    SUM(first_month_sales_litre) AS 销售计划KL,
                    SUM(first_month_require_litre) AS 需求计划KL
                FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
                WHERE report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT('2025-04', '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
                GROUP BY lvl1_org_name, lvl2_org_name
            ) p
        LEFT JOIN 
            -- 实际销售基础数据（组织维度）
            (
                SELECT 
                    oc_lvl1_org_name AS 片区,
                    oc_lvl2_org_name AS 二级片区,
                    SUM(op_sales_litre) AS 实际KL
                FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
                WHERE date_unit = '月'
                  AND line_bill_created_date = '2025-04-01'
                GROUP BY oc_lvl1_org_name, oc_lvl2_org_name
            ) s
          ON p.片区 = s.片区 
         AND p.二级片区 = s.二级片区
        GROUP BY p.片区
    ) org_metrics
-- ==================================================
-- 关联SKU维度指标
-- ==================================================
LEFT JOIN 
    (
        SELECT 
            p.片区,
            CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品层级标记 = 1, ABS(p.销售计划KL - s.实际KL), 0)) / SUM(IF(p.产品层级标记 = 1, p.销售计划KL, 0)))) * 100, 1) AS STRING), '%') AS 重点产品1,
            CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品层级标记 = 0, ABS(p.销售计划KL - s.实际KL), 0)) / SUM(IF(p.产品层级标记 = 0, p.销售计划KL, 0)))) * 100, 1) AS STRING), '%') AS 常规产品1,
            CONCAT(CAST(ROUND((1 - (SUM(ABS(p.销售计划KL - s.实际KL)) / SUM(p.销售计划KL))) * 100, 1) AS STRING), '%') AS 小计1,
            CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品层级标记 = 1, ABS(p.需求计划KL - s.实际KL), 0)) / SUM(IF(p.产品层级标记 = 1, p.需求计划KL, 0)))) * 100, 1) AS STRING), '%') AS 重点产品2,
            CONCAT(CAST(ROUND((1 - (SUM(IF(p.产品层级标记 = 0, ABS(p.需求计划KL - s.实际KL), 0)) / SUM(IF(p.产品层级标记 = 0, p.需求计划KL, 0)))) * 100, 1) AS STRING), '%') AS 常规产品2,
            CONCAT(CAST(ROUND((1 - (SUM(ABS(p.需求计划KL - s.实际KL)) / SUM(p.需求计划KL))) * 100, 1) AS STRING), '%') AS 小计2,
            ROUND((1 - (SUM(ABS(p.需求计划KL - s.实际KL)) / SUM(p.需求计划KL))) * 100, 1) AS 小计2数值
        FROM 
            -- 计划基础数据（SKU维度）
            (
                SELECT 
                    lvl1_org_name AS 片区,
                    product_code AS SKU编码,
                    IF(op_second_brand_name = '重点高端', 1, 0) AS 产品层级标记,
                    SUM(first_month_sales_litre) AS 销售计划KL,
                    SUM(first_month_require_litre) AS 需求计划KL
                FROM crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf
                WHERE report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT('2025-04', '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
                GROUP BY lvl1_org_name, product_code, IF(op_second_brand_name = '重点高端', 1, 0)
            ) p
        LEFT JOIN 
            -- 实际销售基础数据（SKU维度）
            (
                SELECT 
                    oc_lvl1_org_name AS 片区,
                    product_code AS SKU编码,
                    IF(op_second_important_brand_name = '重点高端', 1, 0) AS 产品层级标记,
                    SUM(op_sales_litre) AS 实际KL
                FROM crb_edw_dws_op.dws_op_sales_bill_agg_df
                WHERE date_unit = '月'
                  AND line_bill_created_date = '2025-04-01'
                GROUP BY oc_lvl1_org_name, product_code, IF(op_second_important_brand_name = '重点高端', 1, 0)
            ) s
          ON p.片区 = s.片区 
         AND p.SKU编码 = s.SKU编码 
         AND p.产品层级标记 = s.产品层级标记
        GROUP BY p.片区
    ) sku_metrics
  ON org_metrics.片区 = sku_metrics.片区
ORDER BY org_metrics.片区;
