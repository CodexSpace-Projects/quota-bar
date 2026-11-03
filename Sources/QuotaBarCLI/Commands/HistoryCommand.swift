import Foundation
import QuotaBarCore

extension QuotaBarCLI {
    static func history(_ arguments: [String]) async throws {
        let options = try parseOptions(
            arguments,
            booleanFlags: ["--json"],
            valuedFlags: ["--days", "--currency", "--exchange-rate", "--input-rate", "--cached-input-rate", "--output-rate"]
        )
        let json = options.flags.contains("--json")
        let days = try intValue(options.values["--days"], flag: "--days", range: 1...90) ?? 7
        let inputRate = try doubleValue(options.values["--input-rate"], flag: "--input-rate") ?? 0
        let cachedRate = try doubleValue(options.values["--cached-input-rate"], flag: "--cached-input-rate") ?? 0
        let outputRate = try doubleValue(options.values["--output-rate"], flag: "--output-rate") ?? 0
        let currency = try currencyValue(options.values["--currency"])
        let exchangeRate = try doubleValue(options.values["--exchange-rate"], flag: "--exchange-rate")
        if let exchangeRate, exchangeRate == 0 { throw CLIError.argument("--exchange-rate requires a number greater than zero.") }
        if options.values["--exchange-rate"] != nil, options.values["--currency"] == nil {
            throw CLIError.argument("--exchange-rate requires --currency.")
        }

        let snapshot = try await LocalActivityScanner().scan(days: days)
        let rates = LocalCostRates(inputPerMillion: inputRate, cachedInputPerMillion: cachedRate, outputPerMillion: outputRate)
        let estimates = snapshot.models.map { item -> ModelEstimate in
            if let price = OpenAIPriceCatalog.price(for: item.model) {
                return ModelEstimate(model: item.model, usage: item.usage, price: price, apiEquivalentEstimate: currency.convertFromUSD(price.estimate(item.usage), overrideRate: exchangeRate), pricing: "official")
            }
            let fallback = rates.isConfigured ? currency.convertFromUSD(rates.estimate(item.usage), overrideRate: exchangeRate) : nil
            return ModelEstimate(model: item.model, usage: item.usage, price: nil, apiEquivalentEstimate: fallback, pricing: rates.isConfigured ? "fallback" : "unpriced")
        }
        let totalEstimate = estimates.compactMap(\.apiEquivalentEstimate).reduce(0, +)
        if json {
            struct Output: Encodable {
                let schemaVersion = 2
                let activity: LocalActivitySnapshot
                let models: [ModelEstimate]
                let apiEquivalentEstimate: Double
                let priceCatalogEffectiveDate: String
                let priceCatalogSource: URL
                let currency: String
                let usdToCurrencyRate: Double
                let exchangeRateEffectiveDate: String
                let exchangeRateSource: URL
            }
            print(try encode(Output(activity: snapshot, models: estimates, apiEquivalentEstimate: totalEstimate, priceCatalogEffectiveDate: OpenAIPriceCatalog.effectiveDate, priceCatalogSource: OpenAIPriceCatalog.sourceURL, currency: currency.code, usdToCurrencyRate: exchangeRate ?? currency.bundledUSDExchangeRate, exchangeRateEffectiveDate: CurrencyRateCatalog.effectiveDate, exchangeRateSource: CurrencyRateCatalog.sourceURL)))
        } else {
            for day in snapshot.days {
                print("\(day.date.formatted(date: .numeric, time: .omitted)): \(day.usage.totalTokens) tokens")
            }
            print("total: \(snapshot.total.totalTokens) tokens")
            for item in estimates {
                let cost = item.apiEquivalentEstimate.map { formattedCurrency($0, currency: currency) } ?? "unpriced"
                print("  \(item.model): \(item.usage.totalTokens) tokens · \(cost) [\(item.pricing)]")
            }
            print("API-equivalent estimate: \(formattedCurrency(totalEstimate, currency: currency))")
            print("Official standard API prices checked \(OpenAIPriceCatalog.effectiveDate); not subscription spend.")
        }
    }

}
