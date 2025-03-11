require 'httparty'
require 'concurrent'

class GitHubUsernameChecker
  def initialize(username_file, proxy_file, available_file, unavailable_file)
    @usernames = File.readlines(username_file).map(&:chomp)
    @proxies = File.readlines(proxy_file).map(&:chomp)
    @available_file = available_file
    @unavailable_file = unavailable_file
    @available_usernames = Concurrent::Array.new
    @unavailable_usernames = Concurrent::Array.new
  end

  def check_username(username, proxy)
    options = { timeout: 10 }
    options[:http_proxyaddr] = proxy.split(':')[0]
    options[:http_proxyport] = proxy.split(':')[1]

    response = HTTParty.get("https://api.github.com/users/#{username}", options)

    case response.code
    when 404
      @available_usernames << username
      puts "[+] Username '#{username}' is AVAILABLE."
    when 200
      @unavailable_usernames << username
      puts "[-] Username '#{username}' is UNAVAILABLE."
    when 403
      rate_limit_info = response.headers['x-ratelimit-remaining']
      puts "[!] Rate limit exceeded for proxy #{proxy}. Remaining requests: #{rate_limit_info}."
    else
      puts "[!] Unexpected response for username '#{username}': HTTP #{response.code}."
    end
  rescue Net::OpenTimeout, Net::ReadTimeout
    puts "[!] Timeout occurred while checking '#{username}' using proxy #{proxy}. Proxy may be slow or unresponsive."
  rescue SocketError
    puts "[!] Proxy connection failed for '#{username}' using proxy #{proxy}. Proxy may be invalid or unreachable."
  rescue => e
    puts "[!] Error checking '#{username}': #{e.message}"
  end

  def run
    puts <<~ASCII
      #############################################
      #   GitHub Username Checker - ASCII Edition  #
      #############################################
      #                                           #
      #   Checking usernames with proxies...      #
      #                                           #
      #############################################
    ASCII

    pool = Concurrent::FixedThreadPool.new(@proxies.size)
    @usernames.each_with_index do |username, index|
      proxy = @proxies[index % @proxies.size]
      pool.post { check_username(username, proxy) }
    end
    pool.shutdown
    pool.wait_for_termination

    File.open(@available_file, 'w') do |file|
      @available_usernames.each { |username| file.puts(username) }
    end

    File.open(@unavailable_file, 'w') do |file|
      @unavailable_usernames.each { |username| file.puts(username) }
    end

    puts <<~ASCII
      #############################################
      #               Results Summary             #
      #############################################
      #                                           #
      #   Available usernames saved to:           #
      #     #{@available_file}                    #
      #                                           #
      #   Unavailable usernames saved to:         #
      #     #{@unavailable_file}                  #
      #                                           #
      #############################################
    ASCII
  end
end

# Usage
username_file = 'usernames.txt'
proxy_file = 'proxies.txt'
available_file = 'available.txt'
unavailable_file = 'unavailable.txt'

checker = GitHubUsernameChecker.new(username_file, proxy_file, available_file, unavailable_file)
checker.run