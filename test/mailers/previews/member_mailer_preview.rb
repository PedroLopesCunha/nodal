# Preview all emails at http://localhost:3000/rails/mailers/member_mailer
class MemberMailerPreview < ActionMailer::Preview
  def notificate_customer_order
    order = Order.placed.last
    raise "No placed orders found. Create an order first." unless order
    customer = order.customer
    org_slug = customer.organisation.slug
    MemberMailer.with(customer: customer, order: order, org_slug: org_slug).notificate_customer_order
  end

  def reset_password_instructions
    member = Member.last
    raise "No members found." unless member
    MemberMailer.reset_password_instructions(member, "preview-token-123")
  end

  def team_invitation
    org_member = OrgMember.where.not(invitation_token: nil).last
    raise "No pending invitations found. Invite a team member first." unless org_member
    MemberMailer.team_invitation(org_member)
  end

  def added_to_organisation
    org_member = OrgMember.joins(:member).last
    raise "No org members found." unless org_member
    MemberMailer.added_to_organisation(org_member)
  end
end
