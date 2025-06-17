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
            print("🛒 Attempting to purchase product: \(product.id)")
            let result = try await product.purchase()
            print("📦 Purchase result received: \(result)")
            switch result {
            case .success(let verification):
                print("✅ Purchase success with verification result: \(verification)")
                if case .verified(let transaction) = verification {
                    print("🔒 Transaction verified. Setting subscription status directly.")
                    print("📦 productIDs: \(productIDs)")
                    print("📦 transaction.productID: \(transaction.productID)")
                    if productIDs.contains(transaction.productID) {
                        isSubscribed = true
                        print("✅ isSubscribed set to : \(isSubscribed)")

                    } else {
                        print("⚠️ Verified purchase is not in productIDs list.")
                    }
                } else {
                    print("⚠️ Transaction not verified.")
                }
            default:
                print("ℹ️ Purchase result not successful: \(result)")
            }
        } catch {
            print("❌ Purchase failed with error: \(error)")
        }
    }

    func updateSubscriptionStatus() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIDs.contains(transaction.productID),
               transaction.revocationDate == nil,
               (transaction.expirationDate ?? .distantFuture) > Date() {
                isSubscribed = true
                return
            }
        }
        isSubscribed = false
    }

    func restorePurchases() async {
        do {
            print("🔁 Starting App Store sync for restore...")
            try await AppStore.sync()
            print("🔁 Sync completed. Checking entitlements...")
            await updateSubscriptionStatus()
            print("🔁 Finished restore. isSubscribed = \(isSubscribed)")
        } catch {
            print("❌ Failed to restore: \(error)")
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
