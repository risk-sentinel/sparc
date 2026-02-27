FactoryBot.define do
  factory :conversion_job do
    job_type { "MyString" }
    status { "MyString" }
    document_id { 1 }
    document_type { "MyString" }
    error_message { "MyText" }
  end
end
