-- //////////////////////////////////////////////////////////////////////
-- Queries to get the CSV files which provide the operational point data for the Facilities Web application
-- Written by Regan Sarwas, 2019-08-20 +/-
--
--  TODO: Consider adding facilities in GIS (that have photos?) even if not in FMSS
--        ISEXTANT = 'True' AND ISOUTPARK <> 'Yes' AND P.FACMAINTAIN IN ('NPS','FEDERAL')
-- //////////////////////////////////////////////////////////////////////

-- Make sure we are using the DEFAULT version in SDE
exec sde.set_default

-- Facilities in GIS matching FMSS Location records
SELECT
    -- GIS Attributes
    g.Kind,
    g.FACLOCID AS ID, COALESCE(g.MAPLABEL, '') AS [Name],
    g.Latitude, g.Longitude,
    g.FACLOCID AS Photo_Id, -- FIXME (Pphotos may be linked to GEOMETRYID or FEATUREID or FACASSSETID)
    -- FMSS Attributes
    COALESCE(FORMAT(TRY_CAST(f.CRV AS FLOAT), 'C', 'en-us'), 'Unknown') AS CRV,
    COALESCE(FORMAT(TRY_CAST(f.DM AS FLOAT), 'C', 'en-us'), 'Unknown') AS DM,
    COALESCE(CONVERT(varchar, YEAR(GetDate()) - TRY_CONVERT(INT, f.YearBlt)) + ' yrs', 'Unknown') AS Age,
    f.Description AS [Desc],
    COALESCE(COALESCE(f.PARKNAME, f.PARKNUMB), '')  AS [Park_Id],
    f.Qty + ' ' + f.UM + g.Size as Size,
    f.Parent, f.Status AS [Status]
FROM
    akr_facility2.dbo.FMSSExport AS f
JOIN
    (
    -- Buildings (Center Point)
    SELECT
      'Building' AS Kind,
      FACLOCID, MAPLABEL,
      Shape.STY AS Latitude, Shape.STX AS Longitude,
      '' as Size
    FROM
      akr_facility2.gis.AKR_BLDG_CENTER_PT_evw
    WHERE 
      FACLOCID IS NOT NULL
  UNION ALL
    -- Parking Lots (Centroid)
    SELECT
      'Parking' AS Kind,
      FACLOCID, MAPLABEL,
      Shape.STCentroid().STY AS Latitude, Shape.STCentroid().STX AS Longitude,
      ' (GIS: '+FORMAT(GEOGRAPHY::STGeomFromText(shape.STAsText(),4269).STArea() * 3.28084 * 3.28084,'N0') + 'sf)' as Size
    FROM
      akr_facility2.gis.PARKLOTS_PY_evw
    WHERE 
      FACLOCID IS NOT NULL
  UNION ALL
    -- Trails (All start and end points for a given FACLOCID that are not coincident
    --         with another end or start point respectively)
    SELECT 
      'Trail' AS Kind,
      g1.FACLOCID, g1.MAPLABEL,
      g1.Latitude, g1.Longitude,
      '(GIS: '+FORMAT(g2.Feet,'N0') + 'ft)' as Size
    FROM (
      SELECT 
        FACLOCID, MAPLABEL,
        Latitude, Longitude
      FROM (
          SELECT
            FACLOCID, MAPLABEL,
            Shape.STStartPoint().STY AS Latitude, Shape.STStartPoint().STX AS Longitude
          FROM
            akr_facility2.gis.TRAILS_LN_evw
          WHERE
            FACLOCID IS NOT NULL AND ISBRIDGE = 'No'
        UNION ALL
          SELECT
            FACLOCID, MAPLABEL,
            Shape.STEndPoint().STY AS Latitude, Shape.STEndPoint().STX AS Longitude
          FROM
            akr_facility2.gis.TRAILS_LN_evw
          WHERE
            FACLOCID IS NOT NULL AND ISBRIDGE = 'No'
        ) AS temp
      GROUP BY
        FACLOCID, MAPLABEL, Latitude, Longitude
      HAVING
        COUNT(*) = 1
    ) AS g1
    JOIN (
      SELECT
        FACLOCID,
        SUM(GEOGRAPHY::STGeomFromText(shape.STAsText(),4269).STLength()) * 3.28084 as Feet
      FROM
        akr_facility2.gis.TRAILS_LN_evw
      WHERE
        FACLOCID IS NOT NULL
      GROUP BY
        FACLOCID
    ) AS g2
    ON g1.FACLOCID = g2.FACLOCID
  UNION ALL
    -- Roads (All start and end points for a given FACLOCID that are not coincident
    --         with another end or start point respectively)
    SELECT
      'Road' AS Kind,
      g1.FACLOCID, g1.MAPLABEL,
      g1.Latitude, g1.Longitude,
      ' (GIS: '+FORMAT(g2.Miles,'N2') + 'mi)' as Size
    FROM (
      SELECT 
        FACLOCID, MAPLABEL,
        Latitude, Longitude
      FROM (
          SELECT
            FACLOCID, MAPLABEL,
            Shape.STStartPoint().STY AS Latitude, Shape.STStartPoint().STX AS Longitude
          FROM
            akr_facility2.gis.ROADS_LN_evw
          WHERE
            FACLOCID IS NOT NULL AND ISBRIDGE = 'No'
        UNION ALL
          SELECT
            FACLOCID, MAPLABEL,
            Shape.STEndPoint().STY AS Latitude, Shape.STEndPoint().STX AS Longitude
          FROM
            akr_facility2.gis.ROADS_LN_evw
          WHERE
            FACLOCID IS NOT NULL AND ISBRIDGE = 'No'
        ) AS temp
      GROUP BY
        FACLOCID, MAPLABEL, Latitude, Longitude
      HAVING
        COUNT(*) = 1
    ) AS g1
    JOIN (
      SELECT
        FACLOCID,
        SUM(GEOGRAPHY::STGeomFromText(shape.STAsText(),4269).STLength()) * 0.000621371 as Miles
      FROM
        akr_facility2.gis.ROADS_LN_evw
      WHERE
        FACLOCID IS NOT NULL
      GROUP BY
        FACLOCID
    ) AS g2
    ON g1.FACLOCID = g2.FACLOCID
  UNION ALL
    -- Trail Bridges (Middle vertex, or average of two middle vertices)
    SELECT
      'Bridge' AS Kind,
      FACLOCID, MAPLABEL,
      -- Mid point of bridge
      CASE
        WHEN
          (Shape.STNumPoints() % 2) = 0
        THEN --Even number of vertices
          (Shape.STPointN(Shape.STNumPoints()/2).STY + Shape.STPointN(1 + Shape.STNumPoints()/2).STY)/2.0
        ELSE -- Odd
          Shape.STPointN(1 + Shape.STNumPoints()/2).STY
      END AS Latitude,
      CASE
        WHEN
          (Shape.STNumPoints() % 2) = 0
        THEN --Even
          (Shape.STPointN(Shape.STNumPoints()/2).STX + Shape.STPointN(1 + Shape.STNumPoints()/2).STX)/2.0
        ELSE -- Odd
          Shape.STPointN(1 + Shape.STNumPoints()/2).STX
      END AS Longitude,
      '' AS Size
    FROM
      akr_facility2.gis.ROADS_LN_evw
    WHERE
      FACLOCID IS NOT NULL AND ISBRIDGE = 'Yes'
  UNION ALL
    -- Road Bridges (Middle vertex, or average of two middle vertices)
    SELECT
      'Bridge' AS Kind,
      FACLOCID, MAPLABEL,
      -- Get mid point of bridge
      CASE
        WHEN
          (Shape.STNumPoints() % 2) = 0
        THEN --Even number of vertices
          (Shape.STPointN(Shape.STNumPoints()/2).STY + Shape.STPointN(1 + Shape.STNumPoints()/2).STY)/2.0
        ELSE -- Odd
          Shape.STPointN(1 + Shape.STNumPoints()/2).STY
      END AS Latitude,
      CASE
        WHEN
          (Shape.STNumPoints() % 2) = 0
        THEN --Even
          (Shape.STPointN(Shape.STNumPoints()/2).STX + Shape.STPointN(1 + Shape.STNumPoints()/2).STX)/2.0
        ELSE -- Odd
          Shape.STPointN(1 + Shape.STNumPoints()/2).STX
      END AS Longitude,
      '' AS Size
    FROM
      akr_facility2.gis.TRAILS_LN_evw
    WHERE
      FACLOCID IS NOT NULL AND ISBRIDGE = 'Yes'
  ) AS g 
ON
    g.FACLOCID = f.Location
WHERE
    f.[Type] = 'OPERATING'


-- Items in GIS matching FMSS Asset records

SELECT
  -- GIS
  g.Kind,
  g.FACASSETID AS ID,
  g.[Name] AS [Name],
  g.FACASSETID AS Photo_ID, --FIXME
  g.Latitude, g.Longitude,
  -- FMSS
  f.Location AS Parent,  
  f.[Description] AS [Desc]
FROM
  akr_facility2.dbo.FMSSExport_Asset AS f
JOIN
  (
      SELECT
        -- trail features
        'Trail' AS Kind,
        FACASSETID,
        CASE WHEN TRLFEATTYPE = 'Other' THEN TRLFEATTYPEOTHER ELSE TRLFEATTYPE END + 
          CASE WHEN TRLFEATSUBTYPE is NULL THEN '' ELSE ', ' + TRLFEATSUBTYPE END AS [Name],
        Shape.STY AS Latitude, Shape.STX AS Longitude
      FROM
        akr_facility2.gis.TRAILS_FEATURE_PT_evw
      WHERE
        FACASSETID IS NOT NULL
    UNION ALL
      -- trail attributes (surface material, etc)
      SELECT
        'Trail' AS Kind,
        FACASSETID,
        CASE WHEN TRLATTRTYPE = 'Other' THEN TRLATTRTYPEOTHER ELSE TRLATTRTYPE END + 
          CASE WHEN TRLATTRVALUE is NULL THEN '' ELSE ', ' + TRLATTRVALUE END AS [Name],
        Shape.STY AS Latitude, Shape.STX AS Longitude
      FROM
        akr_facility2.gis.TRAILS_ATTRIBUTE_PT_evw
      WHERE
        FACASSETID IS NOT NULL
    UNION ALL
      -- Buildings (typically out-buildings that are grouped with a main structure)
      SELECT
        'Building' AS Kind,
        FACASSETID,
        MAPLABEL AS [Name],
        Shape.STY AS Latitude, Shape.STX AS Longitude
      FROM
        akr_facility2.gis.AKR_BLDG_CENTER_PT_evw
      WHERE
        FACASSETID IS NOT NULL AND FACLOCID IS NULL
  ) AS g 
ON
  g.FACASSETID = f.Asset
WHERE
  g.FACASSETID IS NOT NULL
