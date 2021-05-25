//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import NIOHTTP1

public protocol AWSWaiterMatcher {
    func match(result: Result<Any, Error>) -> Bool
}

public struct AWSPathMatcher<Object, Value: Equatable>: AWSWaiterMatcher {
    let path: KeyPath<Object, Value>
    let expected: Value

    public init(path: KeyPath<Object, Value>, expected: Value) {
        self.path = path
        self.expected = expected
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            return (output as? Object)?[keyPath: self.path] == self.expected
        case .failure:
            return false
        }
    }
}

public struct AWSAnyPathMatcher<Object, Element, Value: Equatable>: AWSWaiterMatcher {
    let arrayPath: KeyPath<Object, [Element]>
    let elementPath: KeyPath<Element, Value>
    let expected: Value

    public init(arrayPath: KeyPath<Object, [Element]>, elementPath: KeyPath<Element, Value>, expected: Value) {
        self.arrayPath = arrayPath
        self.elementPath = elementPath
        self.expected = expected
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            // get array
            guard let array = (output as? Object)?[keyPath: self.arrayPath] else {
                return false
            }
            return array.first { $0[keyPath: elementPath] == expected } != nil
        case .failure:
            return false
        }
    }
}

public struct AWSAllPathMatcher<Object, Element, Value: Equatable>: AWSWaiterMatcher {
    let arrayPath: KeyPath<Object, [Element]>
    let elementPath: KeyPath<Element, Value>
    let expected: Value

    public init(arrayPath: KeyPath<Object, [Element]>, elementPath: KeyPath<Element, Value>, expected: Value) {
        self.arrayPath = arrayPath
        self.elementPath = elementPath
        self.expected = expected
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            // get array
            guard let array = (output as? Object)?[keyPath: self.arrayPath] else {
                return false
            }
            return array.first { $0[keyPath: elementPath] != expected } == nil
        case .failure:
            return false
        }
    }
}

public struct AWSSuccessMatcher: AWSWaiterMatcher {
    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

public struct AWSErrorStatusMatcher: AWSWaiterMatcher {
    let expectedStatus: Int

    public init(_ status: Int) {
        self.expectedStatus = status
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success:
            return false
        case .failure(let error):
            if let code = (error as? AWSErrorType)?.context?.responseCode.code {
                return code == self.expectedStatus
            } else {
                return false
            }
        }
    }
}

public struct AWSErrorCodeMatcher: AWSWaiterMatcher {
    let expectedCode: String

    public init(_ code: String) {
        self.expectedCode = code
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success:
            return false
        case .failure(let error):
            return (error as? AWSErrorType)?.errorCode == self.expectedCode
        }
    }
}
