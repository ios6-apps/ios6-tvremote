#import "TVDiscovery.h"
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <fcntl.h>
#include <unistd.h>

@interface TVDiscovery () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property (nonatomic, strong) NSMutableArray *list, *pending;
@property (nonatomic, strong) NSNetServiceBrowser *browser;
@property (nonatomic) BOOL scanning;
@property (nonatomic) NSInteger generation;
@end

@implementation TVDiscovery

- (NSArray *)found { return self.list ?: [NSArray array]; }

- (void)changed { if (self.onChange) self.onChange(); }

- (void)add:(NSString *)host name:(NSString *)name {
    if (!self.list) self.list = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.list.count; i++) {
        NSDictionary *d = [self.list objectAtIndex:i];
        if ([[d objectForKey:@"host"] isEqualToString:host]) {
            /* a Bonjour name is nicer than "Android TV 1.2.3.4" */
            if (name && ![[d objectForKey:@"name"] isEqualToString:name] && [[d objectForKey:@"name"] isEqualToString:@"Android TV"]) {
                [self.list replaceObjectAtIndex:i withObject:[NSDictionary dictionaryWithObjectsAndKeys:name, @"name", host, @"host", nil]];
                [self changed];
            }
            return;
        }
    }
    [self.list addObject:[NSDictionary dictionaryWithObjectsAndKeys:name ?: @"Android TV", @"name", host, @"host", nil]];
    [self changed];
}

- (void)start {
    [self stop];
    self.generation++;
    self.pending = [NSMutableArray array];
    self.browser = [[NSNetServiceBrowser alloc] init];
    self.browser.delegate = self;
    [self.browser searchForServicesOfType:@"_androidtvremote2._tcp." inDomain:@"local."];
    [self sweep];
}

- (void)stop {
    self.generation++;
    [self.browser stop]; self.browser = nil;
    self.scanning = NO;
}

#pragma mark Bonjour

- (void)netServiceBrowser:(NSNetServiceBrowser *)b didFindService:(NSNetService *)s moreComing:(BOOL)more {
    [self.pending addObject:s];
    s.delegate = self;
    [s resolveWithTimeout:6];
}

- (void)netServiceDidResolveAddress:(NSNetService *)s {
    for (NSData *a in s.addresses) {
        const struct sockaddr *sa = a.bytes;
        if (sa->sa_family != AF_INET) continue;
        char buf[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &((const struct sockaddr_in *)sa)->sin_addr, buf, sizeof buf);
        [self add:[NSString stringWithUTF8String:buf] name:s.name];
        break;
    }
    [self.pending removeObject:s];
}

- (void)netService:(NSNetService *)s didNotResolve:(NSDictionary *)e { [self.pending removeObject:s]; }

#pragma mark sweep

- (NSString *)localPrefix {
    NSString *prefix = nil;
    struct ifaddrs *list, *p;
    if (getifaddrs(&list) != 0) return nil;
    for (p = list; p; p = p->ifa_next) {
        if (p->ifa_addr && p->ifa_addr->sa_family == AF_INET && !strcmp(p->ifa_name, "en0")) {
            char buf[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &((struct sockaddr_in *)p->ifa_addr)->sin_addr, buf, sizeof buf);
            NSString *ip = [NSString stringWithUTF8String:buf];
            prefix = [ip substringToIndex:[ip rangeOfString:@"." options:NSBackwardsSearch].location + 1];
        }
    }
    freeifaddrs(list);
    return prefix;
}

/* does anything accept a TCP connection on ip:port within the timeout? */
static BOOL portOpen(const char *ip, int port, double timeout) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    struct sockaddr_in a; memset(&a, 0, sizeof a);
    a.sin_len = sizeof a; a.sin_family = AF_INET; a.sin_port = htons(port); inet_pton(AF_INET, ip, &a.sin_addr);
    BOOL ok = NO;
    int r = connect(fd, (struct sockaddr *)&a, sizeof a);
    if (r == 0) ok = YES;
    else if (errno == EINPROGRESS) {
        fd_set w; FD_ZERO(&w); FD_SET(fd, &w);
        struct timeval tv = { (long)timeout, (int)((timeout - (long)timeout) * 1e6) };
        if (select(fd + 1, NULL, &w, NULL, &tv) > 0) { int e = 0; socklen_t l = sizeof e; getsockopt(fd, SOL_SOCKET, SO_ERROR, &e, &l); ok = e == 0; }
    }
    close(fd);
    return ok;
}

/* at most 24 probes at once: hundreds of simultaneous connections make iOS 6 drop most of them */
- (void)sweep {
    NSString *prefix = [self localPrefix];
    if (!prefix) return;
    self.scanning = YES;
    [self changed];
    NSInteger gen = self.generation;
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_semaphore_t gate = dispatch_semaphore_create(24);
    dispatch_group_t group = dispatch_group_create();
    dispatch_async(q, ^{      /* the loop blocks on the semaphore, so it must not run on the main queue */
        for (int i = 1; i <= 254; i++) {
            dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
            if (self.generation != gen) { dispatch_semaphore_signal(gate); break; }
            NSString *ip = [NSString stringWithFormat:@"%@%d", prefix, i];
            dispatch_group_async(group, q, ^{
                if (portOpen(ip.UTF8String, 6466, 0.9)) dispatch_async(dispatch_get_main_queue(), ^{ if (self.generation == gen) [self add:ip name:nil]; });
                dispatch_semaphore_signal(gate);
            });
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{ if (self.generation == gen) { self.scanning = NO; [self changed]; } });
    });
}

@end
