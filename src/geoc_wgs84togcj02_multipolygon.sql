CREATE OR REPLACE FUNCTION "public"."geoc_wgs84togcj02_multipolygon"("source_geom" "public"."geometry")
  RETURNS "public"."geometry" AS $BODY$
DECLARE
    target_parts        geometry[];
    single_polygon      geometry;
    single_polygon_trans geometry;
    final_geom          geometry;
BEGIN
    IF ST_GeometryType(source_geom) != 'ST_MultiPolygon' THEN
        RETURN NULL;
    END IF;

    -- 第一步：逐个子polygon做坐标转换，转换后立即修复
    FOR single_polygon IN SELECT (ST_Dump(source_geom)).geom LOOP

        single_polygon_trans := geoc_wgs84togcj02_polygon(single_polygon);

        -- 转换后检查有效性，无效则用ST_MakeValid修复
        IF single_polygon_trans IS NOT NULL AND NOT ST_IsValid(single_polygon_trans) THEN
            single_polygon_trans := ST_MakeValid(single_polygon_trans);

            -- MakeValid后可能变成GeometryCollection，提取Polygon部分
            IF ST_GeometryType(single_polygon_trans) = 'ST_GeometryCollection' THEN
                single_polygon_trans := ST_CollectionExtract(single_polygon_trans, 3);
            END IF;
        END IF;

        -- 只保留有效的非空结果
        IF single_polygon_trans IS NOT NULL AND ST_IsValid(single_polygon_trans) THEN
            target_parts := array_append(target_parts, single_polygon_trans);
        END IF;

    END LOOP;

    -- 数组为空则返回NULL
    IF target_parts IS NULL OR array_length(target_parts, 1) = 0 THEN
        RETURN NULL;
    END IF;

    -- 第二步：优先用ST_Union合并，失败则降级用ST_Collect
    BEGIN
        SELECT ST_Multi(ST_Union(target_parts)) INTO final_geom;
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            -- ST_Collect不做拓扑运算，不会触发TopologyException
            -- 再套一层MakeValid确保结果合法
            SELECT ST_Multi(
                ST_MakeValid(ST_Collect(target_parts))
            ) INTO final_geom;
        EXCEPTION WHEN OTHERS THEN
            RETURN NULL;
        END;
    END;

    RETURN final_geom;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
