class BundlePriceAllocation
  # The same deterministic cent allocation is used for presentation and the
  # real component lines, so the storefront never invents a second price.
  def self.call(components, total)
    weights = components.to_h { |part| [part.id, part.product_variant.unit_price_cents.to_i * part.quantity] }
    weights = weights.transform_values { 1 } if weights.values.sum.zero?
    base = weights.values.sum
    shares = weights.map { |id, weight| [id, total * weight / base, total * weight % base] }
    shares.sort_by { |id, _, remainder| [-remainder, id] }.first(total - shares.sum { |_, cents, _| cents }).each { |share| share[1] += 1 }
    shares.to_h { |id, cents, _| [id, cents] }
  end
end
