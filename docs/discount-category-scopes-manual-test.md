# Teste manual de campanhas com scopes

Branch: `feature/discount-category-scopes`. Não integrar em `master` antes deste teste e da aprovação do resultado.

As migrations locais já foram aplicadas. Reiniciar o servidor Rails para carregar as novas rotas e configuração. Abrir `http://localhost:3000`, entrar no backoffice da organização e abrir Preços.

## Regressão das regras atuais

- Abrir uma regra antiga de produto/categoria. Confirmar mínimo, datas, condição por linha/conjunta e desconto.
- Confirmar que uma categoria antiga aparece como INCLUDE dessa categoria.
- Confirmar que os escalões antigos estão na campanha “Escalões existentes”, com scope ALL.
- Abrir uma encomenda histórica. O valor guardado mantém-se; encomendas antigas não ganham scopes ou atribuições reconstruídos.

## Categorias conjuntas

Criar uma regra de produto com alvo por categorias, modo INCLUDE, Prata e Bilaminado, mínimo 500 €, condição por valor e scope `summed`, desconto 0.08.

- 300 € Prata + 250 € Bilaminado: desconto nas duas linhas.
- 300 € Prata + 150 € Bilaminado: nenhum desconto desta regra.
- Acrescentar um artigo de outra categoria: não conta nem recebe esta regra.
- Produto associado às duas categorias: conta uma única vez.
- Repetir como desconto específico de cliente.
- Em modo `per_line`, duas linhas abaixo do mínimo não podem desbloquear juntas. As mensagens devem indicar o progresso individual.

## Campanha de encomenda

Criar “Campanha Outubro”, prioridade 1, EXCLUDE Molduras. Adicionar:

- 750 € → 0.07
- 1000 € → 0.08

Os valores de qualificação deste tipo de campanha são **após os descontos das linhas**, sem portes/imposto da encomenda.

- 400 € Prata + 200 € Bilaminado + 200 € Religioso + 300 € Molduras: subtotal elegível 800 €, desconto 56 €, subtotal após este escalão 1044 €.
- 300 € Prata + 200 € Bilaminado + 500 € Molduras: subtotal elegível 500 €, campanha não qualifica.
- 1000 € elegíveis: vence o patamar de 8%.
- Retirar artigos até ficar abaixo do mínimo: desaparece o desconto.
- Usar uma subcategoria de Molduras: também fica excluída.

## Prioridade

Criar outra campanha, prioridade 2, com um desconto maior.

- Ambas qualificam: vence Outubro, independentemente da poupança.
- Outubro não qualifica: a campanha de prioridade 2 pode aplicar-se.
- Confirmar que apenas uma campanha automática aparece no resumo.
- O admin deve indicar claramente “1 é a mais alta”. Prioridades repetidas são rejeitadas; para trocar posições pode usar-se temporariamente uma prioridade livre.

## Checkout e histórico

- Confirmar campanha, subtotal elegível e desconto no carrinho e checkout.
- Finalizar uma encomenda de teste e confirmar o mesmo montante no histórico.
- Editar nome, categorias e percentagem da campanha: a encomenda colocada mantém o snapshot original.
- Confirmar que a soma das atribuições do escalão às linhas coincide com o montante desse escalão e que as linhas excluídas têm atribuição zero.

O limite global de desconto da organização continua a aplicar-se depois dos descontos. As atribuições do escalão são registadas antes desse limite, tal como a dedução apresentada no resumo; o snapshot identifica essa base. Códigos e descontos manuais mantêm os seus próprios âmbitos.

## Stock e preços

- Alterar um preço de variante: o mínimo agregado usa o preço atualizado.
- Com política de remoção, tornar um artigo indisponível: deixa de contar para o mínimo.
- Com política de limite de quantidade por stock, reduzir o stock: o mínimo usa a quantidade final.
- Variantes excluídas continuam a seguir as políticas anteriores dos descontos globais, específicos de cliente e de encomenda.

## Concorrência entre descontos de linha e campanhas de encomenda

- O mínimo é verificado uma única vez sobre os valores após descontos de linha.
- Ambas as regras permitem acumulação: a campanha aplica-se sobre o preço já descontado.
- Pelo menos uma não permite: em cada linha compara-se o preço completo já obtido com o preço da campanha sobre o valor original. Mantém-se o melhor preço; em empate mantém-se o desconto de linha.
- Se várias regras contribuíram para o preço de linha, todas têm de permitir acumulação para esse preço acumular com a campanha.
- A prioridade escolhe a campanha; uma campanha de menor prioridade não toma o seu lugar por oferecer maior poupança.
- Teste: 1.100 € elegíveis, categoria 5%, patamar 1.000 € → 12%. Qualificação: 1.045 €. Sem acumulação: desconto em vigor 132 €, total 968 €. Com ambas acumuláveis: descontos 55 € e 125,40 €, total 919,60 €.
- Teste de fronteira: 1.020 € originais com 5% ficam em 969 € e não desbloqueiam o patamar de 1.000 €, mesmo que substituir os 5% pudesse aumentar a base.
- Artigos fora do scope mantêm os seus descontos de linha. As mensagens “desbloqueado” não devem celebrar descontos substituídos.
- Confirmar os mesmos valores no checkout, histórico, detalhe do backoffice, emails e PDF.
- Campanhas fixas repartem o valor em cêntimos pelas bases elegíveis antes da comparação. Uma parcela que perde para o desconto de linha não é redistribuída; a poupança efetiva pode ser inferior ao valor nominal da campanha.

As atribuições persistidas por linha continuam a representar a poupança adicional sobre a base de qualificação. O snapshot também regista os descontos de linha substituídos; a apresentação soma esses valores para mostrar a poupança completa da campanha e retira-os da rubrica de descontos de linha. Snapshots antigos sem esta informação preservam a acumulação histórica. Não é necessária uma migration nem recalcular encomendas colocadas.

## Envio de preços de campanha para o ERP

- O payload usa o total guardado da linha, após descontos de artigo e a atribuição da campanha, dividido pela quantidade com quatro casas decimais. Não se divide Money por quantidade, para evitar perder a repartição de descontos fixos.
- Uma peça de 100 €, com categoria 5% e campanha 12% exclusivas, é enviada a 88 €. Com ambas acumuláveis é enviada a 83,60 €. Artigos excluídos e preços de artigo superiores mantêm o valor respetivo.
- Editar a campanha ou os descontos depois do checkout não muda estes valores. O envio não avalia regras atuais para encomendas colocadas.
- A soma das atribuições guardadas deve coincidir com o montante automático guardado. Descontos históricos sem repartição por linha, ou repartições inconsistentes, deixam o envio em estado de falha com mensagem explícita; não são reconstruídos.
- Se quatro casas decimais não conseguirem representar o total da linha ao cêntimo para a quantidade indicada, o envio falha antes de chamar o adapter. Não se alteram quantidades nem se criam linhas artificiais para compensar.
- Mantém-se o contrato anterior para impostos, portes, códigos promocionais, descontos manuais e limite global: esta correção cobre preços de artigo e campanhas automáticas de encomenda, antes dos restantes ajustes globais.
- Validar o payload e a nota criada num ambiente de teste do ERP antes do deploy. Os testes automatizados usam um adapter simulado, sem envios reais. Encomendas já sincronizadas não são reenviadas automaticamente.
