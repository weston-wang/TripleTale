//
//  InAppPurchaseManager.swift
//  TripleTale
//
//  Created by Wes Wang on 4/27/25.
//

import StoreKit

@MainActor
class InAppPurchaseManager: ObservableObject {
    @Published var products: [Product] = []
    @Published var isSubscribed = false

    private let productIDs = ["com.tripletale.monthly"]

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(_) = verification {
                    await updateSubscriptionStatus()
                }
            default:
                break
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }

    func updateSubscriptionStatus() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                isSubscribed = true
                return
            }
        }
        isSubscribed = false
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            print("Failed to restore: \(error)")
        }
    }
    
    static func printActiveEntitlements() {
        Task {
            print("📦 Checking active entitlements...")
            for await result in Transaction.currentEntitlements {
                switch result {
                case .verified(let transaction):
                    print("""
                    ✅ Active Subscription:
                    • Product ID: \(transaction.productID)
                    • Purchase Date: \(transaction.purchaseDate)
                    • Expiration Date: \(transaction.expirationDate?.description ?? "None")
                    • Is Upgraded: \(transaction.isUpgraded)
                    """)
                case .unverified(let transaction, let error):
                    print("❌ Unverified transaction: \(transaction.productID), error: \(error)")
                }
            }
        }
    }
}
