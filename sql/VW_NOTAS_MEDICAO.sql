-- =====================================================================
-- Visão: dbo.VW_NOTAS_MEDICAO
-- Banco: BEQ_LWH  (executar com o banco BEQ_LWH ativo)
-- Objetivo: listar as notas fiscais de entrada (LWHSD1010) com o pedido
--           e, quando o pedido foi gerado por medição de contrato
--           (LWHCNE010), o número da medição e do contrato ao lado.
-- Ligação: NF (filial + pedido) -> itens da medição (filial + pedido)
-- Validado: NF 000000303 / filial 13 -> pedido 274480 -> medição 003171
--           Nenhum pedido ligado a mais de uma medição (não duplica notas).
-- Transferências (séries TRA/TRF) excluídas.
-- =====================================================================
CREATE OR ALTER VIEW dbo.VW_NOTAS_MEDICAO AS
WITH NF AS (
    SELECT D1_FILIAL, D1_DOC, D1_SERIE, D1_FORNECE, D1_LOJA,
           MIN(D1_EMISSAO) AS EMISSAO,
           MIN(D1_DTDIGIT) AS LANCAMENTO,
           MAX(D1_PEDIDO)  AS PEDIDO,
           SUM(D1_TOTAL)   AS VALOR_NF
    FROM [BEQ_LWH].[dbo].[LWHSD1010]
    WHERE D1_SERIE NOT IN ('TRA','TRF')
    GROUP BY D1_FILIAL, D1_DOC, D1_SERIE, D1_FORNECE, D1_LOJA
),
MED AS (
    SELECT DISTINCT CNE_FILIAL, CNE_PEDIDO, CNE_CONTRA, CNE_NUMMED
    FROM [BEQ_LWH].[dbo].[LWHCNE010]
    WHERE LTRIM(RTRIM(ISNULL(CNE_PEDIDO,''))) <> ''
)
SELECT NF.D1_FILIAL   AS FILIAL,
       NF.D1_DOC      AS NOTA,
       NF.D1_SERIE    AS SERIE,
       NF.D1_FORNECE  AS FORNECEDOR,
       NF.D1_LOJA     AS LOJA,
       NF.EMISSAO,
       NF.LANCAMENTO,
       NF.VALOR_NF,
       NF.PEDIDO,
       MED.CNE_NUMMED AS MEDICAO,
       MED.CNE_CONTRA AS CONTRATO,
       CASE WHEN MED.CNE_NUMMED IS NOT NULL THEN 'CONTRATO (MEDICAO)'
            WHEN LTRIM(RTRIM(ISNULL(NF.PEDIDO,''))) <> '' THEN 'PEDIDO DE COMPRA'
            ELSE 'SEM PEDIDO' END AS ORIGEM_NOTA
FROM NF
LEFT JOIN MED
       ON MED.CNE_FILIAL = NF.D1_FILIAL
      AND MED.CNE_PEDIDO = NF.PEDIDO
      AND LTRIM(RTRIM(ISNULL(NF.PEDIDO,''))) <> ''
