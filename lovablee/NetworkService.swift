//
//  NetworkService.swift
//  lovablee
//
//  Production-ready network service with timeout, retry, and error handling
//

import Foundation
import Network

final class NetworkService {
    static let shared = NetworkService()

    private let monitor = NWPathMonitor()
    private var isConnected = true

    // URLSession with timeout configuration
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15 // 15 seconds timeout
        config.timeoutIntervalForResource = 30 // 30 seconds for entire request
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private init() {
        // Monitor network connectivity
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
    }

    /// Check if device has network connection
    var hasConnection: Bool {
        return isConnected
    }

    /// Perform a network request with automatic retry on failure
    func performRequest(
        _ request: URLRequest,
        maxRetries: Int = 2,
        retryDelay: TimeInterval = 1.0
    ) async throws -> (Data, HTTPURLResponse) {
        // Check network connectivity first
        guard hasConnection else {
            throw NetworkError.noConnection
        }

        var lastError: Error?

        // Retry logic
        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }

                // Success
                if (200..<300).contains(httpResponse.statusCode) {
                    return (data, httpResponse)
                }

                // Return 401 and 400 (auth errors) so calling code can handle session refresh
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 400 {
                    return (data, httpResponse)
                }

                // Don't retry on other client errors (4xx except 400, 401, and 408)
                if (400..<500).contains(httpResponse.statusCode) && httpResponse.statusCode != 408 {
                    throw NetworkError.httpError(httpResponse.statusCode, data)
                }

                // Retry on server errors (5xx) and 408 (timeout)
                lastError = NetworkError.httpError(httpResponse.statusCode, data)

            } catch let error as URLError {
                // Handle URL-specific errors
                lastError = error

                // Don't retry on certain errors
                if error.code == .cancelled || error.code == .userAuthenticationRequired {
                    throw error
                }

            } catch {
                lastError = error
            }

            // Wait before retry (except on last attempt)
            if attempt < maxRetries {
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }

        // All retries failed
        throw lastError ?? NetworkError.unknown
    }
}

// MARK: - Network Errors

enum NetworkError: LocalizedError {
    case noConnection
    case invalidResponse
    case httpError(Int, Data)
    case timeout
    case unknown

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection. Please check your network and try again."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .httpError(let code, _):
            return "Server error (\(code)). Please try again later."
        case .timeout:
            return "Request timed out. Please check your connection and try again."
        case .unknown:
            return "An unexpected error occurred. Please try again."
        }
    }

    var friendlyMessage: String {
        errorDescription ?? "Something went wrong. Please try again."
    }
}
