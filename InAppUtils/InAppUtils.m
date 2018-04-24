#import "InAppUtils.h"
#import <StoreKit/StoreKit.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import "SKProduct+StringPrice.h"
#import "SKProductDiscount+InAppUtils.h"
#import "SKProductSubscriptionPeriod+InAppUtils.h"

NSString * const PromotedProductPurchasingEventName = @"PromotedProductPurchasing";
NSString * const PromotedProductPurchasedEventName = @"PromotedProductPurchased";
NSString * const PromotedProductPurchaseFailedEventName = @"PromotedProductPurchaseFailed";
NSString * const PromotedProductPurchaseCancelledEventName = @"PromotedProductPurchaseCancelled";

@implementation InAppUtils
{
    NSArray *products;
    NSMutableDictionary *_callbacks;
    NSArray *_promotedProductIds;
    BOOL _promotedPurchase;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _callbacks = [[NSMutableDictionary alloc] init];
        _promotedPurchase = YES;
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents
{
    return @[
             PromotedProductPurchasingEventName,
             PromotedProductPurchasedEventName,
             PromotedProductPurchaseFailedEventName,
             PromotedProductPurchaseCancelledEventName
             ];
}

RCT_EXPORT_METHOD(setAllowedPromotedProducts:(NSArray*)productIdentifiers)
{
    _promotedProductIds = [NSArray arrayWithArray:productIdentifiers];
}

- (BOOL)paymentQueue:(SKPaymentQueue *)queue shouldAddStorePayment:(SKPayment *)payment forProduct:(SKProduct *)product
{
    if ([_promotedProductIds containsObject:product.productIdentifier]) {
        return YES;
    }
    
    // emit error that transaction has been cancelled
    // If you canceled the transaction, provide feedback to the user.
    [self sendEventWithName:PromotedProductPurchaseCancelledEventName
                       body:@{ @"productIdentifier" : product.productIdentifier,
                               @"error" : RCTJSErrorFromNSError(RCTErrorWithMessage(@"Purchase Cancelled"))
                               }];
    
    return NO;
}

- (void)paymentQueue:(SKPaymentQueue *)queue
 updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStateFailed: {
                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    callback(@[RCTJSErrorFromNSError(transaction.error)]);
                    [_callbacks removeObjectForKey:key];
                } else if (_promotedPurchase) {
                    [self sendEventWithName:PromotedProductPurchaseFailedEventName
                                       body:@{
                                              @"error" : RCTJSErrorFromNSError(transaction.error),
                                              @"productIdentifier" : transaction.payment.productIdentifier
                                              }];
                } else {
                    RCTLogWarn(@"No callback registered for transaction with state failed.");
                }
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStatePurchased: {
                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    NSDictionary *purchase = [self getPurchaseData:transaction];
                    callback(@[[NSNull null], purchase]);
                    [_callbacks removeObjectForKey:key];
                } else if (_promotedPurchase) {
                    NSDictionary *purchase = [self getPurchaseData:transaction];
                    [self sendEventWithName:PromotedProductPurchasedEventName
                                       body:purchase];
                } else {
                    RCTLogWarn(@"No callback registered for transaction with state purchased.");
                }
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStateRestored:
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            case SKPaymentTransactionStatePurchasing:
                NSLog(@"purchasing");
                if (_promotedPurchase) {
                    // notify JS about purchase start
                    [self sendEventWithName:PromotedProductPurchasingEventName
                                       body:@{ @"productIdentifier" : transaction.payment.productIdentifier }];
                }
                break;
            case SKPaymentTransactionStateDeferred:
                NSLog(@"deferred");
                break;
            default:
                break;
        }
    }
}

RCT_EXPORT_METHOD(purchaseProductForUser:(NSString *)productIdentifier
                  username:(NSString *)username
                  callback:(RCTResponseSenderBlock)callback)
{
    [self doPurchaseProduct:productIdentifier username:username callback:callback];
}

RCT_EXPORT_METHOD(purchaseProduct:(NSString *)productIdentifier
                  callback:(RCTResponseSenderBlock)callback)
{
    [self doPurchaseProduct:productIdentifier username:nil callback:callback];
}

- (void) doPurchaseProduct:(NSString *)productIdentifier
                  username:(NSString *)username
                  callback:(RCTResponseSenderBlock)callback
{
    _promotedPurchase = NO;
    
    SKProduct *product;
    for(SKProduct *p in products)
    {
        if([productIdentifier isEqualToString:p.productIdentifier]) {
            product = p;
            break;
        }
    }
    
    if(product) {
        SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
        if(username) {
            payment.applicationUsername = username;
        }
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        _callbacks[RCTKeyForInstance(payment.productIdentifier)] = callback;
    } else {
        callback(@[@"invalid_product"]);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        switch (error.code)
        {
            case SKErrorPaymentCancelled:
                callback(@[@"user_cancelled"]);
                break;
            default:
                callback(@[@"restore_failed"]);
                break;
        }
        
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKPaymentTransaction *transaction in queue.transactions){
            if(transaction.transactionState == SKPaymentTransactionStateRestored) {
                
                NSDictionary *purchase = [self getPurchaseData:transaction];
                
                [productsArrayForJS addObject:purchase];
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
            }
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

RCT_EXPORT_METHOD(refreshReceipt:(RCTResponseSenderBlock)callback)
{
    SKReceiptRefreshRequest *refreshReceiptRequest = [[SKReceiptRefreshRequest alloc] init];
    refreshReceiptRequest.delegate = self;
    _callbacks[RCTKeyForInstance(refreshReceiptRequest)] = callback;
    [refreshReceiptRequest start];
}

RCT_EXPORT_METHOD(restorePurchases:(RCTResponseSenderBlock)callback)
{
    NSString *restoreRequest = @"restoreRequest";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

RCT_EXPORT_METHOD(restorePurchasesForUser:(NSString *)username
                  callback:(RCTResponseSenderBlock)callback)
{
    NSString *restoreRequest = @"restoreRequest";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    if(!username) {
        callback(@[@"username_required"]);
        return;
    }
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactionsWithApplicationUsername:username];
}

RCT_EXPORT_METHOD(loadProducts:(NSArray *)productIdentifiers
                  callback:(RCTResponseSenderBlock)callback)
{
    SKProductsRequest *productsRequest = [[SKProductsRequest alloc]
                                          initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
    productsRequest.delegate = self;
    _callbacks[RCTKeyForInstance(productsRequest)] = callback;
    [productsRequest start];
}

RCT_EXPORT_METHOD(canMakePayments: (RCTResponseSenderBlock)callback)
{
    BOOL canMakePayments = [SKPaymentQueue canMakePayments];
    callback(@[@(canMakePayments)]);
}

RCT_EXPORT_METHOD(receiptData:(RCTResponseSenderBlock)callback)
{
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    if (!receiptData) {
        callback(@[@"not_available"]);
    } else {
        callback(@[[NSNull null], [receiptData base64EncodedStringWithOptions:0]]);
    }
}

// SKProductsRequestDelegate protocol method
- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        products = [NSMutableArray arrayWithArray:response.products];
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKProduct *item in response.products) {
            
            NSDictionary *introductoryPrice = nil;
            NSDictionary *subscriptionPeriod = nil;
            if (@available(iOS 11.2, *)) {
                SKProductDiscount *discount = item.introductoryPrice;
                if (discount) {
                    introductoryPrice = @{
                                          @"numberOfPeriods": @(discount.numberOfPeriods),
                                          @"paymentMode": discount.paymentModeString,
                                          @"price" : discount.price,
                                          @"priceString" : [discount priceStringWithLocale:item.priceLocale],
                                          @"subscriptionPeriod" : @{
                                                  @"unit" : discount.subscriptionPeriod.unitString,
                                                  @"numberOfUnits" : @(discount.subscriptionPeriod.numberOfUnits)
                                                  }
                                          };
                }
                
                SKProductSubscriptionPeriod *period = item.subscriptionPeriod;
                if (period) {
                    subscriptionPeriod = @{
                                           @"unit" : period.unitString,
                                           @"numberOfUnits" : @(period.numberOfUnits)
                                           };
                    
                }
            }
            
            NSDictionary *product = @{
                                      @"identifier": item.productIdentifier,
                                      @"price": item.price,
                                      @"currencySymbol": [item.priceLocale objectForKey:NSLocaleCurrencySymbol],
                                      @"currencyCode": [item.priceLocale objectForKey:NSLocaleCurrencyCode],
                                      @"priceString": item.priceString,
                                      @"countryCode": [item.priceLocale objectForKey: NSLocaleCountryCode],
                                      @"downloadable": item.downloadable ? @"true" : @"false",
                                      @"description": item.localizedDescription ? item.localizedDescription : @"",
                                      @"title": item.localizedTitle ? item.localizedTitle : @"",
                                      @"introductoryPrice" : introductoryPrice ? introductoryPrice : [NSNull null],
                                      @"subscriptionPeriod" : subscriptionPeriod ? subscriptionPeriod : [NSNull null]
                                      };
            [productsArrayForJS addObject:product];
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for load product request.");
    }
}

- (void)requestDidFinish:(SKRequest *)request
{
    if([request isKindOfClass:[SKReceiptRefreshRequest class]]) {
        NSString *key = RCTKeyForInstance(request);
        RCTResponseSenderBlock callback = _callbacks[key];
        
        if(callback) {
            callback(@[[NSNull null]]);
            [_callbacks removeObjectForKey:key];
        }
    }
}

// SKProductsRequestDelegate network error
- (void)request:(SKRequest *)request didFailWithError:(NSError *)error{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if(callback) {
        callback(@[RCTJSErrorFromNSError(error)]);
        [_callbacks removeObjectForKey:key];
    }
}

- (NSDictionary *)getPurchaseData:(SKPaymentTransaction *)transaction {
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    
    NSMutableDictionary *purchase = [NSMutableDictionary dictionaryWithDictionary: @{
                                                                                     @"transactionDate": @(transaction.transactionDate.timeIntervalSince1970 * 1000),
                                                                                     @"transactionIdentifier": transaction.transactionIdentifier,
                                                                                     @"productIdentifier": transaction.payment.productIdentifier,
                                                                                     @"transactionReceipt": receiptData ? [receiptData base64EncodedStringWithOptions:0] : [NSNull null]
                                                                                     }];
    // originalTransaction is available for restore purchase and purchase of cancelled/expired subscriptions
    SKPaymentTransaction *originalTransaction = transaction.originalTransaction;
    if (originalTransaction) {
        purchase[@"originalTransactionDate"] = @(originalTransaction.transactionDate.timeIntervalSince1970 * 1000);
        purchase[@"originalTransactionIdentifier"] = originalTransaction.transactionIdentifier;
    }
    
    return purchase;
}

- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

#pragma mark Private

static NSString *RCTKeyForInstance(id instance)
{
    return [NSString stringWithFormat:@"%p", instance];
}

@end

