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
