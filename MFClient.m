//
//  MFClient.m
//  MacFusion2
//
//  Created by Michael Gorbach on 12/10/07.
//  Copyright 2007 Michael Gorbach. All rights reserved.
//

#import "MFClient.h"
#import "MFClientFS.h"
#import "MFClientPlugin.h"
#import "MFConstants.h"

@interface MFClient(PrivateAPI)
- (void)storeFilesystem:(MFClientFS*)fs withUUID:(NSString*)uuid;
- (void)storePlugin:(MFClientPlugin*)plugin withID:(NSString*)id;
- (void)removeFilesystem:(MFClientFS*)fs;
@end

@implementation MFClient

static MFClient* sharedClient = nil;

#pragma mark Singleton methods
+ (MFClient*)sharedClient
{
	if (sharedClient == nil)
	{
		[[self alloc] init];
	}
	
	return sharedClient;
}

+ (MFClient*)allocWithZone:(NSZone*)zone
{
	if (sharedClient == nil)
	{
		sharedClient = [super allocWithZone: zone];
		return sharedClient;
	}
	
	return nil;
}

- (void)registerForGeneralNotifications
{
	NSDistributedNotificationCenter* dnc = [NSDistributedNotificationCenter 
											defaultCenter];
	[dnc addObserver:self
			selector:@selector(handleStatusChangedNotification:)
				name:kMFStatusChangedNotification
			  object:kMFDNCObject];
	[dnc addObserver:self
			selector:@selector(handleFilesystemAddedNotification:)
				name:kMFFilesystemAddedNotification 
			  object:kMFDNCObject];
	[dnc addObserver:self
			selector:@selector(handleFilesystemRemovedNotification:)
				name:kMFFilesystemRemovedNotification 
			  object:kMFDNCObject];
}

- (id) init
{
	self = [super init];
	if (self != nil) {
		[self registerForGeneralNotifications];
		filesystems = [NSMutableArray array];
		plugins = [NSMutableArray array];
	}
	return self;
}


- (void)fillInitialStatus
{
	// Fill plugins
	NSArray* remotePlugins = [server plugins];
	NSArray* remoteFilesystems = [server filesystems];
	
	pluginsDictionary = [NSMutableDictionary dictionaryWithCapacity:10];
	for(id remotePlugin in remotePlugins)
	{
		MFClientPlugin* plugin = [[MFClientPlugin alloc] initWithRemotePlugin: 
								  remotePlugin];
		[self storePlugin: plugin
				   withID: plugin.ID];
	}
	
	// Fill filesystems
	filesystemsDictionary = [NSMutableDictionary dictionaryWithCapacity:10];
	for(id remoteFS in remoteFilesystems)
	{
		MFClientPlugin* plugin = [pluginsDictionary objectForKey: [remoteFS pluginID]];
		MFClientFS* fs = [MFClientFS clientFSWithRemoteFS: remoteFS
											 clientPlugin: plugin];
		[self storeFilesystem: fs
					 withUUID: fs.uuid];
	}
	
}

- (BOOL)establishCommunication
{
	// Set up DO
	id serverObject = [NSConnection rootProxyForConnectionWithRegisteredName:kMFDistributedObjectName
																		host:nil];
	[serverObject setProtocolForProxy:@protocol(MFServerProtocol)];
	server = (id <MFServerProtocol>)serverObject;
	if (serverObject)
	{
		return YES;
	}
	else
	{
		return NO;
	}
}

#pragma mark Notification handling
- (void)handleStatusChangedNotification:(NSNotification*)note
{
//	MFLogS(self, @"Status changed in MFClient");
	NSDictionary* info = [note userInfo];
	NSString* uuid = [info objectForKey: kMFFilesystemUUIDKey];
	MFClientFS* fs = [filesystemsDictionary objectForKey:uuid];
	if (fs)
	{
		[fs handleStatusInfoChangedNotification:note];
	}
	
	if ([delegate respondsToSelector:@selector(clientStatusChanged)])
	{
		[delegate clientStatusChanged];
	}
}

- (void)handleFilesystemAddedNotification:(NSNotification*)note
{
	NSDictionary* info = [note userInfo];
	NSString* uuid = [info objectForKey: kMFFilesystemUUIDKey];
	MFLogS(self, @"Filesystem Added: uuid %@",
		   uuid);
	id remoteFilesystem = [server filesystemWithUUID: uuid];
	if (![self filesystemWithUUID:uuid])
	{
		MFClientPlugin* plugin = [pluginsDictionary objectForKey: [remoteFilesystem pluginID]];
		MFClientFS* fs = [MFClientFS clientFSWithRemoteFS:remoteFilesystem
											 clientPlugin:plugin];
		
		
		[self storeFilesystem:fs
					 withUUID:uuid];
	}
}

- (void)handleFilesystemRemovedNotification:(NSNotification*)note
{
	NSDictionary* info = [note userInfo];
	NSString* uuid = [info objectForKey: kMFFilesystemUUIDKey];
	MFLogS(self, @"Filesystem Deleted: uuid %@",
		   uuid);
	MFClientFS* fs = [self filesystemWithUUID: uuid];
	[self removeFilesystem:fs];
}

#pragma mark Action methods
- (MFClientFS*)newFilesystemWithPlugin:(MFClientPlugin*)plugin
{
	NSAssert(plugin, @"Asked to make new filesystem with nil plugin, MFClient");
	id newRemoteFS = [server newFilesystemWithPluginName: plugin.ID];
	MFClientFS* newFS = [[MFClientFS alloc]	initWithRemoteFS: newRemoteFS
												clientPlugin: plugin];
	[self storeFilesystem:newFS
				 withUUID:newFS.uuid];
	return newFS;
}

#pragma Accessors and Setters

- (void)storePlugin:(MFClientPlugin*)plugin withID:(NSString*)id
{
	NSAssert(id, @"ID null when storing plugin in MfClient");
	[pluginsDictionary setObject: plugin forKey:id];
	if ([plugins indexOfObject: plugin] == NSNotFound)
	{
		[self willChange:NSKeyValueChangeInsertion
		 valuesAtIndexes: [NSIndexSet indexSetWithIndex: [plugins count]]
				  forKey:@"plugins"];
		[plugins addObject: plugin];
		[self didChange:NSKeyValueChangeInsertion
		 valuesAtIndexes: [NSIndexSet indexSetWithIndex: [plugins count]]
				  forKey:@"plugins"];
	}
}

- (void)storeFilesystem:(MFClientFS*)fs withUUID:(NSString*)uuid
{
	NSAssert(fs && uuid, @"FS or UUID is nill when storing fs in MFClient");
	[filesystemsDictionary setObject: fs
							  forKey: uuid];
	if ([filesystems indexOfObject: fs] == NSNotFound)
	{
		[self willChange:NSKeyValueChangeInsertion
		 valuesAtIndexes: [NSIndexSet indexSetWithIndex: [filesystems count]]
				  forKey:@"filesystems"];
		[filesystems addObject: fs];
		[self didChange:NSKeyValueChangeInsertion
		 valuesAtIndexes: [NSIndexSet indexSetWithIndex: [filesystems count]]
				  forKey:@"filesystems"];
	}
}

- (void)removeFilesystem:(MFClientFS*)fs
{
	NSAssert(fs, @"Asked to remove nil fs in MFClient");
	[filesystemsDictionary removeObjectForKey: fs.uuid];
	if ([filesystems indexOfObject:fs] != NSNotFound)
	{
		[self willChange:NSKeyValueChangeRemoval
		 valuesAtIndexes:[NSIndexSet indexSetWithIndex:[filesystems indexOfObject: fs]]
				  forKey:@"filesystems"];
		[filesystems removeObject: fs];
		[self didChange:NSKeyValueChangeRemoval
		 valuesAtIndexes:[NSIndexSet indexSetWithIndex:[filesystems indexOfObject: fs]]
				 forKey:@"filesystems"];
	}
}


- (MFClientFS*)filesystemWithUUID:(NSString*)uuid
{
	NSAssert(uuid, @"uuid nil when requesting FS in MFClient");
	return [filesystemsDictionary objectForKey:uuid];
}

- (MFClientPlugin*)pluginWithID:(NSString*)id
{
	NSAssert(id, @"id nil when requesting plugin in MFClient");
	return [pluginsDictionary objectForKey:id];
}

- (NSArray*)plugins
{
	return (NSArray*)plugins;
}

- (NSArray*)filesystems
{
	return (NSArray*)filesystems;
}

@synthesize delegate;
@end