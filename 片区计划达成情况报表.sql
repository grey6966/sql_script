select 

VV1.lv1 as 片区,
round(pl1,1)  as 销售计划KL,
round(pl2,1)  as 需求计划KL,
round(sl,1) as 实际KL,
pl1_org_r as 销售计划执行,
pl2_org_r as 需求计划执行,
pl1_lev1_sku_r as 重点产品1,
pl1_lev0_sku_r as 常规产品1,
pl1_sku_r     as 小计1,
pl2_lev1_sku_r as 重点产品2,
pl2_lev0_sku_r as 常规产品2,
pl2_sku_r      as 小计2,
'80%'          as 目标准确率,

CONCAT(CAST( ROUND( pl2_sku_num - 80,1)  AS STRING),'%') as 与目标比差异

from 

(
    select lv1,
       sum(pl1) pl1,
       sum(pl2) pl2,
       sum(sl) sl,
       CONCAT(CAST(ROUND((1-(sum(abs( pl1 -sl ))/sum(pl1))) * 100, 1) AS STRING),'%') as pl1_org_r,
       CONCAT(CAST(ROUND((1-(sum(abs( pl2 -sl ))/sum(pl2))) * 100, 1) AS STRING),'%') as pl2_org_r

    from (
        
        select 
        T1.lv1,T1.lv2,T1.pl1,T1.pl2,T2.sl
        from
        (
        select lvl1_org_name lv1,lvl2_org_name lv2,sum(first_month_sales_litre) pl1,sum(first_month_require_litre) pl2 from crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf 
        where report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT('2025-04', '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
        group by lvl1_org_name,lvl2_org_name
        ) T1 
        
        left join
        
        (
        select   oc_lvl1_org_name lv1, oc_lvl2_org_name lv2,sum(op_sales_litre) sl from crb_edw_dws_op.dws_op_sales_bill_agg_df  
        where date_unit = '月'
        and line_bill_created_date = '2025-04-01'
        group by  oc_lvl1_org_name, oc_lvl2_org_name
        )
        
        T2 on T1.lv1 = T2.lv1 and T1.lv2 = T2.lv2
    
    ) V1 group by lv1
) VV1 

left join 

(
    select lv1,
           CONCAT(CAST(ROUND((1-(sum(if( lev =1   ,abs( pl1 -sl ),0))/sum(if( lev =1, pl1 ,0)))) * 100, 1) AS STRING),'%')  as pl1_lev1_sku_r,
           CONCAT(CAST(ROUND((1-(sum(if( lev =0   ,abs( pl1 -sl ),0))/sum(if( lev =0, pl1 ,0)))) * 100, 1) AS STRING),'%')  as pl1_lev0_sku_r,
           CONCAT(CAST(ROUND((1-(sum(abs( pl1 -sl ))/sum( pl1 ))) * 100, 1) AS STRING),'%')  as pl1_sku_r,
           
           CONCAT(CAST(ROUND((1-(sum(if( lev =1   ,abs( pl2 -sl ),0))/sum(if( lev =1, pl2 ,0)))) * 100, 1) AS STRING),'%')  as pl2_lev1_sku_r,
           CONCAT(CAST(ROUND((1-(sum(if( lev =0   ,abs( pl2 -sl ),0))/sum(if( lev =0, pl2 ,0)))) * 100, 1) AS STRING),'%')  as pl2_lev0_sku_r,
           CONCAT(CAST(ROUND((1-(sum(abs( pl2 -sl ))/sum( pl2 ))) * 100, 1) AS STRING),'%')  as pl2_sku_r,
           ROUND((1-(sum(abs( pl2 -sl ))/sum( pl2 ))) * 100, 1) as pl2_sku_num
           
    from (
        select 
        T1.lv1,T1.sku,T1.lev,pl1,pl2,sl
        from
        (
            select lvl1_org_name lv1,product_code sku, if(op_second_brand_name='重点高端',1,0) lev, sum(first_month_sales_litre) pl1,sum(first_month_require_litre) pl2 from crb_edw_dws_op.dws_op_oc_three_month_plan_agg_mf 
            where report_month = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT('2025-04', '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
            group by lvl1_org_name,product_code,if(op_second_brand_name='重点高端',1,0)
        ) T1 
        
        left join
        
        (
            select   oc_lvl1_org_name lv1, product_code sku,if(op_second_important_brand_name='重点高端',1,0) as lev,sum(op_sales_litre) sl from crb_edw_dws_op.dws_op_sales_bill_agg_df  
            where date_unit = '月'
            and line_bill_created_date = '2025-04-01'
            group by  oc_lvl1_org_name, product_code,if(op_second_important_brand_name='重点高端',1,0)
        )
        
        T2 on T1.lv1 = T2.lv1 and T1.sku = T2.sku and T1.lev = T2.lev
    
    ) V2 group by lv1
)  VV2 on VV1.lv1 = VV2.lv1
order by VV1.lv1