-- /*A primeira vista, pensei em criar um modelo de "tabelão" (one big table), pois 
-- garante mais perfornace já que vai processar menos dados (e não preciso criar relacionamentos na ferramenta de visualização que, nesse caso, será o Power BI),
-- e simplesmente porque como esse case é direto, só preciso dos indicadores estratégicos.*/

-- Query: KPIs Mensais por Loja
-- Observações:
--  - Consideramos apenas cupons válidos (canceled = FALSE e staff = FALSE).
--  - Receita líquida = total_value + fee.
--  - Receita bruta = soma de items.total_value (itens vendidos)

-- 1) Base de recibos válidos com valor líquido por cupom
WITH recibos_validos AS (
  SELECT
    identifier,
    shop_id AS loja,
    operation_date,
    DATE_TRUNC(operation_date, MONTH) AS mes, --o DATE_TRUNC me garante o agrupamento mensa depois
    CAST(total_value AS NUMERIC) AS total_value_num, -- converto o tipo para NUMERIC (mais precisão)
    CAST(fee AS NUMERIC) AS fee_num,
    delivery,
    -- net_value: receita do cupom considerando fee
    CAST(total_value AS NUMERIC) + CAST(fee AS NUMERIC) AS net_value
  FROM `case-visio-ai.empresa_highway_dataset.receipts`
  WHERE canceled = FALSE --Apenas cupons válidos (não cancelados, não de funcionários)
    AND staff = FALSE
),

-- 2) Agregação mensal a partir dos recibos válidos da query acima
receipts_mensal AS (
  SELECT
    loja,
    mes,
    SUM(net_value) AS receita_liquida, -- soma
    COUNT(DISTINCT identifier) AS numero_cupons,-- conto os cupons de forma distinta
    SUM(CASE WHEN delivery = TRUE THEN net_value ELSE 0 END) AS receita_delivery -- calculo a receita de Delivey
  FROM recibos_validos
  GROUP BY 1, 2 -- utilizei esse tipo de GROUP BY pra ter facilidade de refatoração, caso mude o nome de uma coluna no SELECT
),

-- 3) Receita bruta (itens) agregada por loja/mês
items_mensal AS (
  SELECT
    r.shop_id AS loja,
    DATE_TRUNC(r.operation_date, MONTH) AS mes,
    SUM(CAST(i.total_value AS NUMERIC)) AS receita_bruta -- Calculo a receita bruta da tabela de Items e referecio ela pelo ALIAS "i"
  FROM `case-visio-ai.empresa_highway_dataset.items` i
  INNER JOIN `case-visio-ai.empresa_highway_dataset.receipts` r -- Faço o JOIN com a Receipts para trazer as lojas somente que tiverem o identifier corresponder na fk da "Items"
    ON i.fk_receipt_identifier = r.identifier
  WHERE r.canceled = FALSE -- novamente determino apenas os cupons válidos
    AND r.staff = FALSE
    AND i.canceled = FALSE
  GROUP BY 1, 2
),

--4) Agregação Mensal dos Descontos
-- Soma o total de descontos aplicados
-- aplico os mesmos conceitos da query acima:
discounts_mensal AS (
  SELECT
    r.shop_id AS loja,
    DATE_TRUNC(r.operation_date, MONTH) AS mes,
    SUM(d.total) AS desconto_total
  FROM `case-visio-ai.empresa_highway_dataset.discounts` d
  INNER JOIN `case-visio-ai.empresa_highway_dataset.receipts` r
    ON r.identifier = d.fk_receipt_identifier
  WHERE
    d.canceled = FALSE
    AND r.canceled = FALSE
    AND r.staff = FALSE
  GROUP BY 1, 2
),

-- 5) Torque mensal: média do net_torque por loja/mês (interpretável)
torque_mensal AS (
  SELECT
    shop_id AS loja,
    DATE_TRUNC(operation_date, MONTH) AS mes,
    AVG(net_torque) AS torque_medio
  FROM `case-visio-ai.empresa_highway_dataset.torque`
  GROUP BY 1, 2
)

-- 6) Tabela final: junta todas as tabelas acima e calcula os KPIs finais por loja/mês
SELECT
  r.loja AS Loja,
  r.mes AS Mes,
  r.receita_liquida AS Receita_Liquida,
  i.receita_bruta AS Receita_Bruta,
  r.numero_cupons AS Numero_Cupons,
  -- Ticket médio = Divisão de: (receita líquida / número de cupons)
  --Utilizei o SAFE_DIVIDE pra não correr risco de ter erros em divisão por zero..
  SAFE_DIVIDE(r.receita_liquida, r.numero_cupons) AS Ticket_Medio,
  d.desconto_total AS Desconto_Total,
  -- Percentual de desconto em relação à receita bruta (se receita_bruta = 0, retorna NULL)
  SAFE_DIVIDE(d.desconto_total, NULLIF(i.receita_bruta,0)) AS Percentual_Desconto,
  t.torque_medio AS Torque_Medio,
  r.receita_delivery AS Receita_Delivery,
  SAFE_DIVIDE(r.receita_delivery, NULLIF(r.receita_liquida,0)) AS Percentual_Receita_Delivery

FROM receipts_mensal r
LEFT JOIN items_mensal i
  ON r.loja = i.loja AND r.mes = i.mes
  --o uso do LEFT JOIN aqui é pra garantir que os cupons sem descontos (desconto = null) também apareçam..
LEFT JOIN discounts_mensal d 
  ON r.loja = d.loja AND r.mes = d.mes
  -- para pegar métricas financeiras diárias (agregadas no mês).
LEFT JOIN torque_mensal t
  ON r.loja = t.loja AND r.mes = t.mes

ORDER BY r.loja, r.mes;
--Agrupo por loja e por mês

