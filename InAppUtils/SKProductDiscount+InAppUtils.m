#import "SKProductDiscount+InAppUtils.h"

@implementation SKProductDiscount (InAppUtils)
- (NSString *)paymentModeString
{
    switch (self.paymentMode) {
        case SKProductDiscountPaymentModePayAsYouGo:
            return @"PayAsYouGo";
        case SKProductDiscountPaymentModePayUpFront:
            return @"PayUpFront";
        case SKProductDiscountPaymentModeFreeTrial:
            return @"FreeTrial";
    }
}

- (NSString *)priceString
{
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.formatterBehavior = NSNumberFormatterBehavior10_4;
    formatter.numberStyle = NSNumberFormatterCurrencyStyle;
    formatter.locale = self.priceLocale;
    
    return [formatter stringFromNumber:self.price];
}

@end
