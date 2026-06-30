# SimpleApm (Rails Engine)

A lightweight Redis-backed Rails engine for web request performance monitoring and slow request tracing.

SimpleApm records request performance by day:

- The slowest requests, 500 by default.
- The slowest 20 requests for each action.
- Average response time for each action.
- Slow request details and related SQL details, trimming excess records.
- Average and slowest response time, request count, and other metrics in 10-minute intervals, with charts.
- External HTTP request duration during each request.

The web UI supports English and Chinese. English is used by default, and users can switch languages from the top-right corner.

## How It Works

SimpleApm records request-level data around Rack and uses Redis for storage and aggregation.

The core data flow is based on [Active Support Instrumentation](https://guides.rubyonrails.org/active_support_instrumentation.html).

Instrumentation events are processed by a long-running worker thread so request handling does not block on metric aggregation.

Memory usage is collected with [get_process_mem](https://github.com/schneems/get_process_mem). In Linux testing, collection takes less than 1 ms.

## Screenshots

- Dashboard
![Dashboard](public/dashbord.png)

- Slow Requests
![Slow Requests](public/slow_requests.png)

- Action List
![Action List](public/action_list.png)

- Request Info
![Request Info](public/request_info.png)

- Action Info
![Action Info](public/action_detail.png)

- Data Management
![Data Management](public/data-manage.png)

## Usage

Mount the engine in your Rails routes:

```ruby
# routes.rb
mount SimpleApm::Engine => "/apm"
```

Or run the installer:

```bash
rails generate simple_apm:install
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem "simple_apm"
```

Then run:

```bash
bundle
```

## Contributing

Issues and pull requests are welcome.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
