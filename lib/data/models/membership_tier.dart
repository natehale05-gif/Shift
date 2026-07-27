/// A SHIFT AI Club membership purchase tier, as listed on shiftai.club.
/// Presented for demo/informational purposes only in this build — selecting
/// a tier never initiates a real purchase.
class MembershipTier {
  final String id;
  final String name;
  final String priceLabel;
  final String billingNote;
  final String creditsLabel;
  final List<String> perks;
  final bool highlighted;

  const MembershipTier({
    required this.id,
    required this.name,
    required this.priceLabel,
    required this.billingNote,
    required this.creditsLabel,
    required this.perks,
    this.highlighted = false,
  });

  static const List<MembershipTier> all = [
    MembershipTier(
      id: 'shift_membership',
      name: 'SHIFT Membership',
      priceLabel: '\$99/mo',
      billingNote: 'Recurring · cancel anytime · earn from day one',
      creditsLabel: '20,000 credits / month',
      perks: [
        '20,000 Suite credits every month',
        'Earn 20% ConnectPay',
        'Full access to the SHIFT AI Suite',
        'Unlock all 5 streams at Bronze, or \$1,000 in credits',
      ],
    ),
    MembershipTier(
      id: 'standard_club',
      name: 'SHIFT Standard Club Membership',
      priceLabel: '\$499',
      billingNote: '\$499 today, then \$99/mo · all streams from day one',
      creditsLabel: '100,000 credits + full suite',
      perks: [
        '100,000 Suite credits to start',
        'All 5 EcoPay streams unlocked — earn from day one',
        'Full access to the SHIFT AI Suite',
        'Then \$99/mo (begins in 30 days) · 20,000 credits/mo',
      ],
      highlighted: true,
    ),
    MembershipTier(
      id: 'founders_club',
      name: "Founder's Club Membership",
      priceLabel: '\$1,000',
      billingNote: 'One-time · Founder\'s badge',
      creditsLabel: '200,000 credits',
      perks: [
        'Access to the full SHIFT AI Suite',
        'EcoPay attribution active across 5 streams',
        'Real-time settlement on every credit',
        "Standard Founder's badge",
        '\$99 monthly fee waived first month',
      ],
    ),
    MembershipTier(
      id: 'bronze_enterprise',
      name: 'Bronze Club Membership',
      priceLabel: '\$5,000',
      billingNote: 'Small Business · 1–5 employees · \$1M–\$3M annual revenue',
      creditsLabel: '1,000,000 credits',
      perks: [
        'Access to the full SHIFT AI Suite',
        'EcoPay attribution active across 5 streams',
        'Real-time settlement on every credit',
        "Standard Founder's badge",
      ],
    ),
  ];
}

/// One of the five EcoPay earning streams. Purely descriptive here — no real
/// money is tracked or moved by this app.
class PayoutStream {
  final String id;
  final String name;
  final String role;
  final String description;

  const PayoutStream({
    required this.id,
    required this.name,
    required this.role,
    required this.description,
  });

  static const List<PayoutStream> all = [
    PayoutStream(
      id: 'club_pay',
      name: 'ClubPay',
      role: 'Choose Your Club Membership',
      description:
          'Earn based on your Club Membership level: Bronze 5% · Silver 10% · Gold 15% · Platinum 20%.',
    ),
    PayoutStream(
      id: 'credit_pay',
      name: 'CreditPay',
      role: 'The Capital Holder',
      description:
          'Earn on every credit purchased across the ecosystem. The bigger your stack, the bigger your share.',
    ),
    PayoutStream(
      id: 'content_pay',
      name: 'ContentPay',
      role: 'The Content Creator',
      description:
          'Create content that drives demand — your fingerprint on the sale earns a dynamic % of the ecosystem.',
    ),
    PayoutStream(
      id: 'connect_pay',
      name: 'ConnectPay',
      role: 'The Connector',
      description:
          'Refer a customer. Earn 20% the moment they purchase AI credits — every time.',
    ),
    PayoutStream(
      id: 'compete_pay',
      name: 'CompetePay',
      role: 'The Top Performer',
      description:
          'Top earners split a real prize pool — 10% of gross revenue company-wide, weekly.',
    ),
  ];
}
