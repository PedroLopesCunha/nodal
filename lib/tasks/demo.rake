# lib/tasks/demo.rake
#
# Usage:
#   rails demo:load[peixe]
#
# What it does:
#   - Wipes products, categories, orders, shopping lists for nodal-demo org
#   - Repopulates with industry-specific data
#   - Leaves customers, discounts and org untouched
#
# Add new verticals by adding a new `when` branch in load_industry_data

namespace :demo do

  DEMO_SLUG = "nodal-demo".freeze

  desc "Load industry-specific demo data. Usage: rails demo:load[peixe]"
  task :load, [:industry] => :environment do |_, args|
    industry = args[:industry]&.downcase

    unless industry
      puts "❌ Please specify an industry. Example: rails demo:load[peixe]"
      exit 1
    end

    org = Organisation.find_by(slug: DEMO_SLUG)
    unless org
      puts "❌ Demo org '#{DEMO_SLUG}' not found. Run db:seed first."
      exit 1
    end

    puts "🔄 Loading demo data for industry: #{industry.upcase}"
    puts "   Org: #{org.name} (#{org.slug})"
    puts ""

    ActiveRecord::Base.transaction do
      DemoLoader.new(org).wipe!
      puts "  🗑️  Wiped existing products, categories, orders and shopping lists"

      case industry
      when "peixe", "fish"
        DemoLoader::Peixe.new(org).seed!
      else
        puts "❌ Unknown industry '#{industry}'. Available: peixe"
        raise ActiveRecord::Rollback
      end
    end

    puts ""
    puts "✅ Demo data loaded for: #{industry.upcase}"
    puts "   Storefront : /#{DEMO_SLUG}"
    puts "   Back-office: /#{DEMO_SLUG}/bo"
  end

end

# =============================================================================
# DEMO LOADER BASE
# =============================================================================
class DemoLoader
  attr_reader :org

  def initialize(org)
    @org = org
  end

  def wipe!
    # Order of deletion matters — respect FK constraints

    # Shopping lists
    ShoppingListItem
      .joins(:shopping_list)
      .where(shopping_lists: { organisation_id: org.id })
      .delete_all
    ShoppingList.where(organisation_id: org.id).delete_all

    # Orders
    order_ids = Order.where(organisation_id: org.id).pluck(:id)
    OrderItem.where(order_id: order_ids).delete_all
    Order.where(id: order_ids).delete_all

    # Category <> Product joins
    product_ids = Product.where(organisation_id: org.id).pluck(:id)
    CategoryProduct.where(product_id: product_ids).delete_all

    # Variant attribute values
    variant_ids = ProductVariant.where(organisation_id: org.id).pluck(:id)
    VariantAttributeValue.where(product_variant_id: variant_ids).delete_all

    # Product available values & product-attribute links
    ProductAvailableValue.where(product_id: product_ids).delete_all
    ProductProductAttribute.where(product_id: product_ids).delete_all

    # Variants
    ProductVariant.where(organisation_id: org.id).delete_all

    # Products
    Product.where(organisation_id: org.id).delete_all

    # Nullify category references in discounts before deleting categories
    category_ids = Category.where(organisation_id: org.id).pluck(:id)
    ProductDiscount.where(category_id: category_ids).update_all(category_id: nil) if category_ids.any?
    CustomerProductDiscount.where(category_id: category_ids).update_all(category_id: nil) if category_ids.any?

    # Categories
    Category.where(organisation_id: org.id).delete_all
  end

  # ---------------------------------------------------------------------------
  # Helpers shared across all industry loaders
  # ---------------------------------------------------------------------------

  def create_category!(name:, slug:, description:, color:, position:)
    Category.create!(
      organisation: org,
      name:         name,
      slug:         "#{DEMO_SLUG}-#{slug}",
      description:  description,
      color:        color,
      position:     position
    )
  end

  # Simple product — updates the auto-created default variant with stock info
  def create_simple_product!(category:, name:, sku:, price_cents:, unit_desc:, min_qty:, stock: 200, description: nil)
    slug = "#{DEMO_SLUG}-#{sku.downcase.gsub(/[^a-z0-9]/, '-')}"
    product = Product.create!(
      organisation:    org,
      category:        category,
      name:            name,
      slug:            slug,
      sku:             sku,
      description:     description,
      unit_price:      price_cents,
      unit_description: unit_desc,
      min_quantity:    min_qty,
      available:       true,
      has_variants:    false
    )

    # Update the auto-created default variant with stock
    product.product_variants.first!.update!(
      stock_quantity: stock,
      track_stock:    true
    )

    product
  end

  # Product with multiple named variants and proper attribute configuration
  # attribute_name: e.g. "Calibre", "Tamanho"
  # Each variant hash must include :name (used as the attribute value)
  def create_variant_product!(category:, name:, sku:, unit_desc:, min_qty:, attribute_name:, description: nil, variants: [])
    slug = "#{DEMO_SLUG}-#{sku.downcase.gsub(/[^a-z0-9]/, '-')}"
    base_price = variants.first[:price_cents]

    product = Product.create!(
      organisation:    org,
      category:        category,
      name:            name,
      slug:            slug,
      sku:             sku,
      description:     description,
      unit_price:      base_price,
      unit_description: unit_desc,
      min_quantity:    min_qty,
      available:       true,
      has_variants:    true,
      variants_generated: true
    )

    # 1. Find or create the ProductAttribute for this org
    attr = ProductAttribute.find_or_create_by!(organisation: org, name: attribute_name) do |a|
      a.position = ProductAttribute.where(organisation: org).count + 1
    end

    # 2. Link attribute to product
    ProductProductAttribute.create!(product: product, product_attribute: attr, position: 1)

    # 3. Create each variant with its attribute value
    variants.each_with_index do |v, i|
      # Find or create the attribute value
      attr_value = ProductAttributeValue.find_or_create_by!(product_attribute: attr, value: v[:name]) do |av|
        av.position = i + 1
      end

      # Mark this value as available for this product
      ProductAvailableValue.create!(product: product, product_attribute_value: attr_value)

      # Create the variant
      pv = ProductVariant.create!(
        organisation:         org,
        product:              product,
        sku:                  "#{sku}-#{v[:sku_suffix]}",
        name:                 v[:name],
        unit_price_cents:     v[:price_cents],
        unit_price_currency:  org.currency,
        stock_quantity:       v[:stock] || 150,
        track_stock:          true,
        available:            true,
        is_default:           i == 0,
        position:             i + 1
      )

      # Link variant to its attribute value
      VariantAttributeValue.create!(product_variant: pv, product_attribute_value: attr_value)
    end

    product
  end

  def create_order!(customer:, status:, placed_at: nil, items: [])
    order = Order.create!(
      organisation:             org,
      customer:                 customer,
      order_number:             "DEMO-#{SecureRandom.hex(4).upcase}",
      status:                   status,
      payment_status:           status == "completed" ? "paid" : "pending",
      placed_at:                placed_at,
      receive_on:               placed_at ? placed_at.to_date + 3.days : nil,
      shipping_amount_cents:    org.shipping_cost_cents,
      shipping_amount_currency: org.shipping_cost_currency,
      delivery_method:          "delivery"
    )

    items.each do |product, variant, qty|
      OrderItem.create!(
        order:            order,
        product:          product,
        product_variant:  variant,
        quantity:         qty,
        unit_price:       variant.unit_price_cents,
        discount_percentage: 0.0
      )
    end

    order
  end

  def create_shopping_list!(customer:, name:, notes: nil, items: [])
    list = ShoppingList.create!(
      organisation: org,
      customer:     customer,
      name:         name,
      notes:        notes
    )

    items.each do |product, variant, qty|
      ShoppingListItem.create!(
        shopping_list:    list,
        product:          product,
        product_variant:  variant,
        quantity:         qty
      )
    end

    list
  end

end

# =============================================================================
# INDUSTRY: PEIXE (Fish & Seafood - Portugal)
# =============================================================================
class DemoLoader::Peixe < DemoLoader

  def seed!
    puts "  🐟 Seeding Peixe & Marisco catalogue..."

    categories = seed_categories!
    products   = seed_products!(categories)
    seed_orders!(products)
    seed_shopping_lists!(products)

    puts "  ✅ #{org.products.count} produtos | #{org.orders.count} encomendas"
  end

  private

  def seed_categories!
    fresco = create_category!(
      name:        "Peixe Fresco",
      slug:        "peixe-fresco",
      description: "Peixe fresco do dia, capturado nas melhores águas portuguesas",
      color:       "#1565C0",
      position:    1
    )

    congelado = create_category!(
      name:        "Peixe Congelado",
      slug:        "peixe-congelado",
      description: "Peixe e marisco ultracongelados para máxima frescura",
      color:       "#0288D1",
      position:    2
    )

    marisco = create_category!(
      name:        "Marisco",
      slug:        "marisco",
      description: "Marisco fresco e vivo — amêijoas, gambas, percebes e mais",
      color:       "#E65100",
      position:    3
    )

    conservas = create_category!(
      name:        "Conservas & Fumados",
      slug:        "conservas-fumados",
      description: "Conservas artesanais e fumados de alta qualidade",
      color:       "#4E342E",
      position:    4
    )

    { fresco: fresco, congelado: congelado, marisco: marisco, conservas: conservas }
  end

  def seed_products!(cats)
    products = {}

    # -------------------------------------------------------------------------
    # SIMPLE PRODUCTS (10)
    # -------------------------------------------------------------------------

    products[:sardinha] = create_simple_product!(
      category:    cats[:fresco],
      name:        "Sardinha Fresca",
      sku:         "PX-SAR-FRE",
      price_cents: 380,
      unit_desc:   "kg",
      min_qty:     10,
      stock:       500,
      description: "Sardinha atlântica fresca, ideal para grelhar. Calibre 40/60."
    )

    products[:dourada] = create_simple_product!(
      category:    cats[:fresco],
      name:        "Dourada do Atlântico",
      sku:         "PX-DOU-FRE",
      price_cents: 890,
      unit_desc:   "kg",
      min_qty:     5,
      stock:       200,
      description: "Dourada fresca de aquacultura certificada. Peso médio 400g."
    )

    products[:robalo] = create_simple_product!(
      category:    cats[:fresco],
      name:        "Robalo Fresco",
      sku:         "PX-ROB-FRE",
      price_cents: 1190,
      unit_desc:   "kg",
      min_qty:     5,
      stock:       150,
      description: "Robalo selvagem do Atlântico Norte. Peixe nobre de sabor intenso."
    )

    products[:lula] = create_simple_product!(
      category:    cats[:fresco],
      name:        "Lula Fresca Limpa",
      sku:         "PX-LUL-FRE",
      price_cents: 750,
      unit_desc:   "kg",
      min_qty:     5,
      stock:       180,
      description: "Lula já limpa e pronta a cozinhar. Captura do dia."
    )

    products[:polvo] = create_simple_product!(
      category:    cats[:fresco],
      name:        "Polvo do Alto Mar",
      sku:         "PX-POL-FRE",
      price_cents: 820,
      unit_desc:   "kg",
      min_qty:     5,
      stock:       160,
      description: "Polvo cozido e congelado. Pronto a fatiar ou grelhar."
    )

    products[:mexilhao] = create_simple_product!(
      category:    cats[:congelado],
      name:        "Mexilhão Cozido Congelado",
      sku:         "PX-MEX-CON",
      price_cents: 290,
      unit_desc:   "caixa 1kg",
      min_qty:     10,
      stock:       400,
      description: "Mexilhão cozido e ultracongelado. Caixa de 1kg."
    )

    products[:pota] = create_simple_product!(
      category:    cats[:congelado],
      name:        "Pota em Anéis Congelada",
      sku:         "PX-POT-CON",
      price_cents: 450,
      unit_desc:   "caixa 1kg",
      min_qty:     10,
      stock:       300,
      description: "Anéis de pota ultracongelados, calibrados. Caixa 1kg."
    )

    products[:ameiJoa] = create_simple_product!(
      category:    cats[:marisco],
      name:        "Amêijoa Boa",
      sku:         "MS-AME-BOA",
      price_cents: 960,
      unit_desc:   "kg",
      min_qty:     5,
      stock:       200,
      description: "Amêijoa boa viva, depurada e certificada. Origem: Ria de Aveiro."
    )

    products[:atum_conserva] = create_simple_product!(
      category:    cats[:conservas],
      name:        "Atum em Azeite — Lata 120g",
      sku:         "CON-ATU-AZE-120",
      price_cents: 285,
      unit_desc:   "lata",
      min_qty:     24,
      stock:       600,
      description: "Atum em azeite virgem extra. Pesca sustentável certificada."
    )

    products[:sardinha_conserva] = create_simple_product!(
      category:    cats[:conservas],
      name:        "Sardinha em Azeite — Lata 125g",
      sku:         "CON-SAR-AZE-125",
      price_cents: 195,
      unit_desc:   "lata",
      min_qty:     24,
      stock:       800,
      description: "Sardinha portuguesa em azeite. Produto artesanal, conserva premium."
    )

    puts "    ✅ 10 produtos simples"

    # -------------------------------------------------------------------------
    # PRODUCT WITH 4 VARIANTS: Bacalhau (Especial / Corrente / Popular / Desfiado)
    # -------------------------------------------------------------------------
    products[:bacalhau] = create_variant_product!(
      category:    cats[:conservas],
      name:        "Bacalhau Salgado Seco",
      sku:         "PX-BAC-SAL",
      unit_desc:   "kg",
      min_qty:     10,
      attribute_name: "Calibre",
      description: "Bacalhau norueguês salgado e seco. Disponível em vários calibres.",
      variants: [
        { sku_suffix: "ESP", name: "Especial (acima 800g)", price_cents: 1290, stock: 200 },
        { sku_suffix: "COR", name: "Corrente (400g–800g)",  price_cents: 980,  stock: 300 },
        { sku_suffix: "POP", name: "Popular (200g–400g)",   price_cents: 720,  stock: 350 },
        { sku_suffix: "DES", name: "Desfiado",              price_cents: 850,  stock: 250 }
      ]
    )

    puts "    ✅ 1 produto com 4 variantes (Bacalhau)"

    # -------------------------------------------------------------------------
    # PRODUCT WITH 3 VARIANTS: Camarão (Pequeno / Médio / Grande)
    # -------------------------------------------------------------------------
    products[:camarao] = create_variant_product!(
      category:    cats[:marisco],
      name:        "Camarão Congelado",
      sku:         "MS-CAM-CON",
      unit_desc:   "caixa 1kg",
      min_qty:     5,
      attribute_name: "Calibre",
      description: "Camarão ultracongelado, descascado e sem veio. Vários calibres.",
      variants: [
        { sku_suffix: "PEQ", name: "Pequeno 40/60",  price_cents: 680, stock: 400 },
        { sku_suffix: "MED", name: "Médio 30/40",    price_cents: 890, stock: 350 },
        { sku_suffix: "GRD", name: "Grande 20/30",   price_cents: 1190, stock: 250 }
      ]
    )

    # -------------------------------------------------------------------------
    # PRODUCT WITH 3 VARIANTS: Salmão Fresco (Posta / Filete / Inteiro)
    # -------------------------------------------------------------------------
    products[:salmao] = create_variant_product!(
      category:    cats[:fresco],
      name:        "Salmão do Atlântico",
      sku:         "PX-SAL-FRE",
      unit_desc:   "kg",
      min_qty:     5,
      attribute_name: "Formato",
      description: "Salmão fresco do Atlântico Norte. Disponível em diferentes formatos.",
      variants: [
        { sku_suffix: "POS", name: "Posta",    price_cents: 1050, stock: 200 },
        { sku_suffix: "FIL", name: "Filete",   price_cents: 1290, stock: 180 },
        { sku_suffix: "INT", name: "Inteiro",  price_cents: 880,  stock: 150 }
      ]
    )

    puts "    ✅ 2 produtos com 3 variantes (Camarão, Salmão)"

    products
  end

  # ---------------------------------------------------------------------------
  # ORDERS
  # ---------------------------------------------------------------------------
  def seed_orders!(p)
    customers = Customer.where(organisation_id: org.id).limit(3).to_a

    return if customers.empty?

    c1, c2, c3 = customers[0], customers[1], customers[2]

    bacalhau_esp = p[:bacalhau].product_variants.find_by(name: "Especial (acima 800g)")
    bacalhau_cor = p[:bacalhau].product_variants.find_by(name: "Corrente (400g–800g)")
    bacalhau_des = p[:bacalhau].product_variants.find_by(name: "Desfiado")
    camarao_med  = p[:camarao].product_variants.find_by(name: "Médio 30/40")
    camarao_grd  = p[:camarao].product_variants.find_by(name: "Grande 20/30")
    salmao_fil   = p[:salmao].product_variants.find_by(name: "Filete")
    salmao_pos   = p[:salmao].product_variants.find_by(name: "Posta")

    # --- Customer 1: 2 completed + 1 in_process ---
    if c1
      create_order!(
        customer:  c1,
        status:    "completed",
        placed_at: 40.days.ago,
        items: [
          [p[:bacalhau],       bacalhau_cor, 50],
          [p[:sardinha],       p[:sardinha].product_variants.first, 30],
          [p[:atum_conserva],  p[:atum_conserva].product_variants.first, 48]
        ]
      )
      create_order!(
        customer:  c1,
        status:    "completed",
        placed_at: 12.days.ago,
        items: [
          [p[:bacalhau],          bacalhau_esp, 25],
          [p[:camarao],           camarao_grd,  20],
          [p[:sardinha_conserva], p[:sardinha_conserva].product_variants.first, 72]
        ]
      )
      create_order!(
        customer:  c1,
        status:    "in_process",
        items: [
          [p[:bacalhau], bacalhau_des, 30],
          [p[:polvo],    p[:polvo].product_variants.first, 15],
          [p[:mexilhao], p[:mexilhao].product_variants.first, 20]
        ]
      )
    end

    # --- Customer 2: 2 completed + 1 in_process ---
    if c2
      create_order!(
        customer:  c2,
        status:    "completed",
        placed_at: 55.days.ago,
        items: [
          [p[:salmao],   salmao_fil,  30],
          [p[:dourada],  p[:dourada].product_variants.first, 20],
          [p[:lula],     p[:lula].product_variants.first, 15]
        ]
      )
      create_order!(
        customer:  c2,
        status:    "completed",
        placed_at: 18.days.ago,
        items: [
          [p[:salmao],  salmao_pos,  25],
          [p[:camarao], camarao_med, 30],
          [p[:ameiJoa], p[:ameiJoa].product_variants.first, 20]
        ]
      )
      create_order!(
        customer:  c2,
        status:    "in_process",
        items: [
          [p[:salmao],  salmao_fil,  20],
          [p[:robalo],  p[:robalo].product_variants.first, 10],
          [p[:pota],    p[:pota].product_variants.first, 15]
        ]
      )
    end

    # --- Customer 3: 2 completed + 1 in_process ---
    if c3
      create_order!(
        customer:  c3,
        status:    "completed",
        placed_at: 35.days.ago,
        items: [
          [p[:ameiJoa],       p[:ameiJoa].product_variants.first, 30],
          [p[:camarao],       camarao_grd, 25],
          [p[:bacalhau],      bacalhau_cor, 40]
        ]
      )
      create_order!(
        customer:  c3,
        status:    "completed",
        placed_at: 8.days.ago,
        items: [
          [p[:atum_conserva],     p[:atum_conserva].product_variants.first, 96],
          [p[:sardinha_conserva], p[:sardinha_conserva].product_variants.first, 72],
          [p[:polvo],             p[:polvo].product_variants.first, 10]
        ]
      )
      create_order!(
        customer:  c3,
        status:    "in_process",
        items: [
          [p[:camarao], camarao_med, 20],
          [p[:dourada], p[:dourada].product_variants.first, 15],
          [p[:lula],    p[:lula].product_variants.first, 10]
        ]
      )
    end

    puts "    ✅ 9 encomendas (6 concluídas + 3 em curso)"
  end

  # ---------------------------------------------------------------------------
  # SHOPPING LISTS
  # ---------------------------------------------------------------------------
  def seed_shopping_lists!(p)
    customers = Customer.where(organisation_id: org.id).limit(3).to_a
    return if customers.empty?

    c1, c2, c3 = customers[0], customers[1], customers[2]

    bacalhau_cor = p[:bacalhau].product_variants.find_by(name: "Corrente (400g–800g)")
    camarao_med  = p[:camarao].product_variants.find_by(name: "Médio 30/40")
    salmao_fil   = p[:salmao].product_variants.find_by(name: "Filete")

    if c1
      create_shopping_list!(
        customer: c1,
        name:     "Encomenda Semanal",
        notes:    "Reposição semanal de bacalhau e conservas",
        items: [
          [p[:bacalhau],       bacalhau_cor, 50],
          [p[:atum_conserva],  p[:atum_conserva].product_variants.first, 48],
          [p[:sardinha],       p[:sardinha].product_variants.first, 30]
        ]
      )
    end

    if c2
      create_shopping_list!(
        customer: c2,
        name:     "Frescos da Semana",
        notes:    "Peixe fresco para o menu semanal",
        items: [
          [p[:salmao],  salmao_fil, 20],
          [p[:robalo],  p[:robalo].product_variants.first, 10],
          [p[:dourada], p[:dourada].product_variants.first, 15]
        ]
      )
    end

    if c3
      create_shopping_list!(
        customer: c3,
        name:     "Marisco Mensal",
        notes:    "Marisco para eventos e catering",
        items: [
          [p[:ameiJoa], p[:ameiJoa].product_variants.first, 30],
          [p[:camarao], camarao_med, 20],
          [p[:mexilhao], p[:mexilhao].product_variants.first, 25]
        ]
      )
    end

    puts "    ✅ 3 listas de compras (1 por cliente)"
  end
end
