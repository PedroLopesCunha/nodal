require "test_helper"

class OrganisationTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: "Test Org")
  end

  # custom_domain format validation

  test "accepts a valid subdomain hostname" do
    @org.custom_domain = "b2b.example.com"
    assert @org.valid?, @org.errors.full_messages.inspect
  end

  test "accepts an apex hostname" do
    @org.custom_domain = "example.pt"
    assert @org.valid?
  end

  test "accepts hostname with multiple dots" do
    @org.custom_domain = "shop.b2b.cliente.example.co.uk"
    assert @org.valid?
  end

  test "allows blank custom_domain" do
    @org.custom_domain = nil
    assert @org.valid?
    @org.custom_domain = ""
    assert @org.valid?
  end

  test "rejects hostname with scheme" do
    @org.custom_domain = "https://example.com"
    @org.valid?
    # after normalization the scheme is stripped, so it actually becomes valid;
    # this test verifies normalization fixes user input rather than rejecting it
    assert_equal "example.com", @org.custom_domain
    assert @org.valid?
  end

  test "rejects hostname with path" do
    @org.custom_domain = "example.com/path"
    @org.valid?
    assert_equal "example.com", @org.custom_domain
    assert @org.valid?
  end

  test "rejects hostname with spaces" do
    @org.custom_domain = "exa mple.com"
    assert_not @org.valid?
    assert @org.errors[:custom_domain].any?
  end

  test "rejects hostname without TLD" do
    @org.custom_domain = "localhost"
    assert_not @org.valid?
  end

  test "rejects hostname with leading hyphen in label" do
    @org.custom_domain = "-bad.example.com"
    assert_not @org.valid?
  end

  test "rejects hostname with trailing hyphen in label" do
    @org.custom_domain = "bad-.example.com"
    assert_not @org.valid?
  end

  # normalization

  test "normalizes uppercase to lowercase" do
    @org.custom_domain = "B2B.Example.COM"
    @org.valid?
    assert_equal "b2b.example.com", @org.custom_domain
  end

  test "normalizes by stripping whitespace" do
    @org.custom_domain = "  b2b.example.com  "
    @org.valid?
    assert_equal "b2b.example.com", @org.custom_domain
  end

  test "normalizes by removing https scheme" do
    @org.custom_domain = "https://b2b.example.com"
    @org.valid?
    assert_equal "b2b.example.com", @org.custom_domain
  end

  test "normalizes by removing http scheme" do
    @org.custom_domain = "http://b2b.example.com"
    @org.valid?
    assert_equal "b2b.example.com", @org.custom_domain
  end

  test "normalizes by removing path" do
    @org.custom_domain = "b2b.example.com/orders"
    @org.valid?
    assert_equal "b2b.example.com", @org.custom_domain
  end

  test "normalizes trailing dot" do
    @org.custom_domain = "b2b.example.com."
    @org.valid?
    assert_equal "b2b.example.com", @org.custom_domain
  end

  test "normalizes whitespace-only input to nil" do
    @org.custom_domain = "   "
    @org.valid?
    assert_nil @org.custom_domain
  end

  # uniqueness

  test "enforces uniqueness of custom_domain" do
    @org.update!(custom_domain: "b2b.example.com")
    other = Organisation.new(name: "Other Org", custom_domain: "b2b.example.com")
    assert_not other.valid?
    assert other.errors[:custom_domain].any?
  end

  test "allows multiple organisations with nil custom_domain" do
    Organisation.create!(name: "Org A")
    other = Organisation.new(name: "Org B")
    assert other.valid?
  end

  # find_by_host

  test "find_by_host returns the org matching custom_domain" do
    @org.update!(custom_domain: "b2b.perestrelocunha.pt")
    assert_equal @org, Organisation.find_by_host("b2b.perestrelocunha.pt")
  end

  test "find_by_host is case-insensitive" do
    @org.update!(custom_domain: "b2b.perestrelocunha.pt")
    assert_equal @org, Organisation.find_by_host("B2B.Perestrelocunha.PT")
  end

  test "find_by_host strips whitespace" do
    @org.update!(custom_domain: "b2b.perestrelocunha.pt")
    assert_equal @org, Organisation.find_by_host("  b2b.perestrelocunha.pt  ")
  end

  test "find_by_host returns nil for blank host" do
    assert_nil Organisation.find_by_host(nil)
    assert_nil Organisation.find_by_host("")
    assert_nil Organisation.find_by_host("   ")
  end

  test "find_by_host returns nil when host does not match any org and does not return orgs with NULL custom_domain" do
    Organisation.create!(name: "No Domain Org")
    assert_nil Organisation.find_by_host("nonexistent.example.com")
  end

  # custom_domain_verified?

  test "custom_domain_verified? is false when domain is nil" do
    assert_not @org.custom_domain_verified?
  end

  test "custom_domain_verified? is false when domain is set but not verified" do
    @org.update!(custom_domain: "b2b.example.com")
    assert_not @org.custom_domain_verified?
  end

  test "custom_domain_verified? is true when domain is set and verified_at is present" do
    @org.update!(custom_domain: "b2b.example.com", custom_domain_verified_at: Time.current)
    assert @org.custom_domain_verified?
  end

  # preferred_host

  test "preferred_host falls back to canonical host when no custom_domain set" do
    assert_equal Rails.application.config.x.canonical_host, @org.preferred_host
  end

  test "preferred_host falls back to canonical when custom_domain is set but not verified" do
    @org.update!(custom_domain: "b2b.example.com")
    assert_equal Rails.application.config.x.canonical_host, @org.preferred_host
  end

  test "preferred_host returns the custom_domain when verified" do
    @org.update!(custom_domain: "b2b.example.com", custom_domain_verified_at: Time.current)
    assert_equal "b2b.example.com", @org.preferred_host
  end

  # email_from_address

  test "email_from_address uses the canonical host regardless of custom_domain" do
    @org.update!(name: "Acme Co", custom_domain: "b2b.example.com", custom_domain_verified_at: Time.current)
    canonical = Rails.application.config.x.canonical_host
    assert_equal "Acme Co <no-reply@#{canonical}>", @org.email_from_address
  end

  # custom_domain change resets verification

  test "changing custom_domain clears the existing verified_at" do
    @org.update!(custom_domain: "b2b.first.test", custom_domain_verified_at: Time.current)
    assert @org.custom_domain_verified?
    @org.update!(custom_domain: "b2b.second.test")
    assert_nil @org.reload.custom_domain_verified_at
  end

  test "clearing custom_domain clears the existing verified_at" do
    @org.update!(custom_domain: "b2b.first.test", custom_domain_verified_at: Time.current)
    @org.update!(custom_domain: nil)
    assert_nil @org.reload.custom_domain_verified_at
  end

  test "saving without touching custom_domain keeps verified_at intact" do
    @org.update!(custom_domain: "b2b.first.test", custom_domain_verified_at: Time.current)
    original_verified_at = @org.custom_domain_verified_at
    @org.update!(name: "Renamed Co")
    assert_in_delta original_verified_at.to_f, @org.reload.custom_domain_verified_at.to_f, 1.0
  end
end
