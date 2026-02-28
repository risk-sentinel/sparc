# Building the SSP-TPR-Manager

## Setup

Create a .env file (use dotenv-rails gem)

```bash
# .env
DATABASE_URL=postgresql://localhost/ssp_tpr_manager_development
REDIS_URL=redis://localhost:6379/0

# AWS (for production file storage)
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-east-1
AWS_BUCKET=your-bucket-name

# Optional: External API integration
EXTERNAL_API_URL=https://api.example.com
EXTERNAL_API_KEY=your_api_key
```

Add to Gemfile:

```ruby
gem 'dotenv-rails', groups: [:development, :test]
```

## Docker Support

### Dockerfile

```docker
FROM ruby:3.2.0

RUN apt-get update -qq && apt-get install -y nodejs postgresql-client

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
```

### docker-compose.yaml

```yaml
version: '3.8'

services:
  db:
    image: postgres:15
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: ssp_tpr_manager_development
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  web:
    build: .
    command: bash -c "rm -f tmp/pids/server.pid && bundle exec rails s -b '0.0.0.0'"
    volumes:
      - .:/app
      - bundle_cache:/usr/local/bundle
    ports:
      - "3000:3000"
    depends_on:
      - db
      - redis
    environment:
      DATABASE_URL: postgresql://postgres:password@db:5432/ssp_tpr_manager_development
      REDIS_URL: redis://redis:6379/0

  sidekiq:
    build: .
    command: bundle exec sidekiq
    volumes:
      - .:/app
      - bundle_cache:/usr/local/bundle
    depends_on:
      - db
      - redis
    environment:
      DATABASE_URL: postgresql://postgres:password@db:5432/ssp_tpr_manager_development
      REDIS_URL: redis://redis:6379/0

volumes:
  postgres_data:
  bundle_cache:
```

## Extending to TPR updates

### app/services/tpr_update_service.rb

```ruby
class TprUpdateService
  def initialize(tpr_document)
    @document = tpr_document
  end
  
  def update_control(control_id, field_updates)
    control = @document.tpr_controls.find_by!(control_id: control_id)
    
    field_updates.each do |field_name, new_value|
      field = control.tpr_control_fields.find_or_initialize_by(field_name: field_name)
      
      # Only update if field is editable
      if field.editable
        field.field_value = new_value
        field.save!
      else
        raise StandardError, "Field '#{field_name}' is not editable"
      end
    end
    
    control
  end
  
  def bulk_update(updates)
    ActiveRecord::Base.transaction do
      updates.each do |control_id, field_updates|
        update_control(control_id, field_updates)
      end
    end
  end
  
  def update_test_status(control_id, status, results)
    control = @document.tpr_controls.find_by!(control_id: control_id)
    
    status_field = control.tpr_control_fields.find_or_create_by!(field_name: 'test_status')
    status_field.update!(field_value: status)
    
    results_field = control.tpr_control_fields.find_or_create_by!(field_name: 'test_results')
    results_field.update!(field_value: results)
    
    date_field = control.tpr_control_fields.find_or_create_by!(field_name: 'test_date')
    date_field.update!(field_value: Date.today.to_s)
    
    control
  end
end
```

### Add API endpoint for TPR updates

```ruby
# app/controllers/api/v1/tpr_documents_controller.rb
module Api
  module V1
    class TprDocumentsController < ApplicationController
      skip_before_action :verify_authenticity_token
      
      def update_fields
        tpr_document = TprDocument.find(params[:id])
        update_service = TprUpdateService.new(tpr_document)
        
        begin
          update_service.bulk_update(params[:controls])
          
          render json: {
            success: true,
            message: 'Controls updated successfully',
            data: tpr_document.to_json_data
          }
        rescue StandardError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
      
      def update_test_status
        tpr_document = TprDocument.find(params[:id])
        update_service = TprUpdateService.new(tpr_document)
        
        begin
          control = update_service.update_test_status(
            params[:control_id],
            params[:status],
            params[:results]
          )
          
          render json: {
            success: true,
            message: 'Test status updated',
            control: control.to_hash
          }
        rescue StandardError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
```
