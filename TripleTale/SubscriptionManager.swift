//
//  SubscriptionManager.swift
//  TripleTale
//
//  Created by Wes Wang on 4/26/25.
//

import StoreKit

@MainActor
class SubscriptionManager: ObservableObject {
    @Published var products: [Product] = []

    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: ["com.tripletale.monthly"])
            self.products = storeProducts
        } catch {
            print("Error loading products: \(error)")
        }
    }

    func purchase(product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                print("Purchase verified: \(verification)")
            default:
                print("Purchase cancelled or failed")
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }
}
