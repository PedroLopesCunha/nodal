# Desconto de cliente sincronizado com o ERP

O campo `Customer#erp_discount_percentage` pertence à empresa e é gerido pelo ERP. Usa percentagens entre 0 e 100, até quatro casas decimais: `20` representa 20%. É independente dos `CustomerDiscount` definidos no Nodal.

## Ativação

1. Aplicar a migração `20261111120000`.
2. Em Definições ERP → mapeamento de clientes, associar **Desconto ERP (%)** à coluna de desconto da ficha do cliente. Disponível nos adapters Firebird e Custom API.
3. Sincronizar clientes e confirmar o valor na ficha da empresa no back office.
4. Validar uma encomenda de teste no ERP: artigo de 100 €, promoção Nodal de 10%, desconto ERP de 20% → loja 72 €, push 90 €, ERP 72 € (sem IVA).

Sem mapeamento, a sincronização preserva o valor existente. Com mapeamento, zero, NULL ou vazio removem o desconto. Valores inválidos são rejeitados; não são convertidos silenciosamente para zero. Não se tenta adivinhar a coluna de origem.

Se o desconto da ficha ERP tiver sido anteriormente reproduzido numa regra de desconto interna, rever essa regra antes de ativar a sincronização: as duas condições são cumulativas. O código não elimina regras comerciais existentes.

## Cálculo e apresentação

- O catálogo, variantes e preços dinâmicos incluem o desconto de cliente depois dos descontos Nodal aplicáveis à linha.
- Os cards mostram o preço base riscado e o preço do cliente em linhas separadas, sem texto adicional. Na página do produto, uma indicação em itálico mostra a percentagem de cliente incluída. O desconto ERP isolado não cria badges de promoção nem um painel vazio de descontos.
- Carrinho, checkout, histórico, emails e PDF incluem o desconto. Os resumos discriminam a redução para explicar a diferença entre o subtotal Nodal e o total pago.
- A qualificação de campanhas e a competição/acumulação de descontos internos continuam a usar os valores Nodal. O limite máximo de desconto da organização aplica-se aos descontos Nodal; o desconto ERP é aplicado depois.
- O cálculo de IVA usa o subtotal com o desconto ERP. O progresso de portes grátis usa o subtotal do carrinho já com desconto ERP, mantendo a regra existente de avaliação antes dos cupões/descontos manuais.
- A encomenda guarda a percentagem na finalização. Encomendas anteriores à migração ficam com zero e não passam a usar retroativamente o desconto atual do cliente.
- Alterações do desconto ERP num carrinho existente usam a política de aviso/confirmação de alterações de preço já existente.

## Envio ao ERP

`OrderItem#discount_percentage` mantém apenas os descontos internos. `OrderLinePricing#export_totals` calcula os valores Nodal por linha, incluindo campanhas guardadas, cupões, descontos manuais e limite máximo; distribui ajustes globais preservando os cêntimos. A reposição de valores pelo limite máximo nunca aumenta uma linha acima do preço base.

O `OrderPushService` usa estes valores sem o desconto ERP e mantém a validação da representação em preços unitários com quatro casas decimais. Não divide preços pelo desconto para recuperar valores: funciona também com desconto ERP de 100%.

O desconto ERP é arredondado por linha, sobre o valor com descontos Nodal, e somado no total. O ERP real deve aplicar a mesma ordem e regra de arredondamento; validar no circuito de teste antes de ativar para os clientes.
