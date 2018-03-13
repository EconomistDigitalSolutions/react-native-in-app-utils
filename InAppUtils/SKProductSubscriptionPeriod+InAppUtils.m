#import "SKProductSubscriptionPeriod+InAppUtils.h"

@implementation SKProductSubscriptionPeriod (InAppUtils)

- (NSString *)unitString
{
    switch (self.unit) {
        case SKProductPeriodUnitDay:
            return @"day";
        case SKProductPeriodUnitWeek:
            return @"week";
        case SKProductPeriodUnitMonth:
            return @"month";
        case SKProductPeriodUnitYear:
            return @"year";
    }
}

@end
