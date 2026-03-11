FactoryBot.define do
  factory :catalog_control do
    control_family
    sequence(:control_id) { |n| "#{(control_family&.code || 'AC').downcase}-#{n}" }
    label { control_id&.upcase&.gsub(/\.(\d+)/) { "(#{$1})" } }
    sort_id { control_id&.gsub(/(\d+)/) { $1.rjust(2, "0") } }
    title { Faker::Lorem.sentence }
    priority { %w[P0 P1 P2 P3].sample }
    baseline_impact { "LOW, MODERATE, HIGH" }
    guidance_data { {} }

    trait :with_params do
      params_data do
        [
          { "id" => "#{control_id.downcase.tr(' ', '-')}_prm_1",
            "label" => "organization-defined personnel or roles" },
          { "id" => "#{control_id.downcase.tr(' ', '-')}_prm_2",
            "label" => "organization-defined frequency" }
        ]
      end
    end

    trait :with_select_param do
      params_data do
        [
          { "id" => "#{control_id.downcase.tr(' ', '-')}_prm_1",
            "select" => { "how-many" => "one-or-more",
                          "choice" => [ "removes", "disables" ] } }
        ]
      end
    end

    trait :with_guidelines_param do
      params_data do
        [
          { "id" => "#{control_id.downcase.tr(' ', '-')}_prm_1",
            "label" => "personnel or roles",
            "guidelines" => [ { "prose" => "some assessment guidance" } ] }
        ]
      end
    end
  end
end
