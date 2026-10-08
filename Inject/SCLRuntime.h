#import <Foundation/Foundation.h>
#import <os/log.h>

NS_ASSUME_NONNULL_BEGIN

os_log_t SCLLog(void);

#define SCLLogInfo(fmt, ...) os_log(SCLLog(), "[SimCamLite] " fmt, ##__VA_ARGS__)
#define SCLLogError(fmt, ...) os_log_error(SCLLog(), "[SimCamLite] " fmt, ##__VA_ARGS__)

BOOL SCLSwizzleInstance(Class cls, SEL original, SEL replacement);
BOOL SCLSwizzleClass(Class cls, SEL original, SEL replacement);
void SCLInstallSafeDealloc(Class cls);
void SCLLeakObject(id object);

@interface SCLWeakBox : NSObject
@property (nonatomic, weak, nullable) id value;
+ (instancetype)boxWithValue:(nullable id)value;
@end

NS_ASSUME_NONNULL_END
