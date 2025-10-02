FROM ruby:3.2-slim

WORKDIR /app

# Install build dependencies if needed
RUN apt-get update && \
    apt-get install -y build-essential && \
    rm -rf /var/lib/apt/lists/*

# Copy Gemfile and install dependencies
COPY Gemfile ./
RUN bundle install

# Copy application files
COPY . .

# Run the bot
CMD ["ruby", "bot.rb"]