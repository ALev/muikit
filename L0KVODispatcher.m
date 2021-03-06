//
//  L0MicroBindings.m
//  MuiKit
//
//  Created by ∞ on 17/07/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "L0KVODispatcher.h"
#import "L0KVODictionaryAdditions.h"

L0UniquePointerConstant(kL0MicroBindingsObservingContext);

@implementation L0KVODispatcher

- (id) initWithTarget:(id) t;
{
	if (self = [super init]) {
		target = t;
		selectorsByKeyPathsAndObjects = [NSMutableDictionary new];
	}
		
	return self;
}

- (void) dealloc;
{
	for (NSValue* ptr in selectorsByKeyPathsAndObjects) {
		id object = [ptr nonretainedObjectValue];
		
		for (NSString* keyPath in [selectorsByKeyPathsAndObjects objectForKey:ptr])
			[object removeObserver:self forKeyPath:keyPath];
	}
	
	[selectorsByKeyPathsAndObjects release];
	[super dealloc];
}

#pragma mark -
#pragma mark Observation

- (void) observe:(NSString*) keyPath ofObject:(id) object usingSelector:(SEL) selector options:(NSKeyValueObservingOptions) options;
{
	NSValue* ptr = [NSValue valueWithNonretainedObject:object];
	NSMutableDictionary* selectorsByKeyPath = [selectorsByKeyPathsAndObjects objectForKey:ptr];
	NSString* selectorString = [selectorsByKeyPath objectForKey:keyPath];
	
	
	if (!selectorsByKeyPath) {
		selectorsByKeyPath = [NSMutableDictionary dictionary];
		[selectorsByKeyPathsAndObjects setObject:selectorsByKeyPath forKey:ptr];
	}

	BOOL alreadyRegistered = (selectorString != nil);

	selectorString = NSStringFromSelector(selector);		
	[selectorsByKeyPath setObject:selectorString forKey:keyPath];
		
	if (!alreadyRegistered)
		[object addObserver:self forKeyPath:keyPath options:options context:(void*) kL0MicroBindingsObservingContext];
}

- (void) observeValueForKeyPath:(NSString*) keyPath ofObject:(id) object change:(NSDictionary*) change context:(void*) context;
{
	if (context != kL0MicroBindingsObservingContext) return;
	
	NSValue* ptr = [NSValue valueWithNonretainedObject:object];
	NSMutableDictionary* selectorsByKeyPath = [selectorsByKeyPathsAndObjects objectForKey:ptr];
	NSString* selectorString = [selectorsByKeyPath objectForKey:keyPath];

	if (selectorString)
		[target performSelector:NSSelectorFromString(selectorString) withObject:object withObject:change];
}

- (void) endObserving:(NSString*) keyPath ofObject:(id) object;
{
	NSValue* ptr = [NSValue valueWithNonretainedObject:object];
	NSMutableDictionary* selectorsByKeyPath = [selectorsByKeyPathsAndObjects objectForKey:ptr];
	NSString* selectorString = [selectorsByKeyPath objectForKey:keyPath];

	[selectorsByKeyPath removeObjectForKey:keyPath];
	if ([selectorsByKeyPath count] == 0)
		[selectorsByKeyPathsAndObjects removeObjectForKey:ptr];
	
	[object removeObserver:self forKeyPath:keyPath];
}

#pragma mark -
#pragma mark To-many dispatch.

// insertion =>   - (void) inArrayOfObject:(id) o inserted:(id) i atIndex:(NSUInteger) idx;
// removal =>     - (void) inArrayOfObject:(id) o removed:(id) i atIndex:(NSUInteger) idx;
// replacement => - (void) inArrayOfObject:(id) o replaced:(id) oldObject with:(id) newObject atIndex:(NSUInteger) idx;
- (void) forEachArrayChange:(NSDictionary*) change forObject:(id) o invokeSelectorForInsertion:(SEL) insertion removal:(SEL) removal replacement:(SEL) replacement;
{
	NSKeyValueChange changeKind = L0KVOChangeKind(change);
	NSInvocation* insertionInv = nil, * removalInv = nil, * replacementInv = nil;
	
	// Set up the invocation stuff.
	if (changeKind == NSKeyValueChangeInsertion || (changeKind == NSKeyValueChangeReplacement && !replacement)) {
		NSMethodSignature* insertSig = [target methodSignatureForSelector:insertion];
		insertionInv = [NSInvocation invocationWithMethodSignature:insertSig];
		
		[insertionInv setTarget:target];
		[insertionInv setSelector:insertion];
		[insertionInv setArgument:&o atIndex:2];
	}
	
	if (changeKind == NSKeyValueChangeRemoval || (changeKind == NSKeyValueChangeReplacement && !replacement)) {
		NSMethodSignature* removeSig = [target methodSignatureForSelector:removal];
		removalInv = [NSInvocation invocationWithMethodSignature:removeSig];
		
		[removalInv setTarget:target];
		[removalInv setSelector:removal];
		[removalInv setArgument:&o atIndex:2];
	}	

	if (changeKind == NSKeyValueChangeReplacement && replacement) {
		NSMethodSignature* replacementSig = [target methodSignatureForSelector:replacement];
		replacementInv = [NSInvocation invocationWithMethodSignature:replacementSig];
		
		[replacementInv setTarget:target];
		[replacementInv setSelector:replacement];
		[replacementInv setArgument:&o atIndex:2];
	}
	
	
	NSIndexSet* indexes = L0KVOChangedIndexes(change);
	
	NSUInteger arrayIndex = [indexes firstIndex], changeIndex = 0;
	NSArray* insertions = (changeKind == NSKeyValueChangeRemoval)? nil : L0KVOChangedValue(change);
	NSArray* removals = (changeKind == NSKeyValueChangeInsertion)? nil : L0KVOPreviousValue(change);

	while (arrayIndex != NSNotFound) {		
		id insertedObject = [insertions objectAtIndex:changeIndex];
		id removedObject = [removals objectAtIndex:changeIndex];
		
		if (changeKind == NSKeyValueChangeRemoval || (changeKind == NSKeyValueChangeReplacement && !replacement)) {
			[removalInv setArgument:&removedObject atIndex:3];
			[removalInv setArgument:&arrayIndex atIndex:4];
			[removalInv invoke];			
		}
		
		if (changeKind == NSKeyValueChangeInsertion || (changeKind == NSKeyValueChangeReplacement && !replacement)) {
			[insertionInv setArgument:&insertedObject atIndex:3];
			[insertionInv setArgument:&arrayIndex atIndex:4];
			[insertionInv invoke];
		}
		
		if (changeKind == NSKeyValueChangeReplacement && replacement) {
			[replacementInv setArgument:&removedObject atIndex:3];
			[replacementInv setArgument:&insertedObject atIndex:4];
			[replacementInv setArgument:&arrayIndex atIndex:5];
			[replacementInv invoke];
		}
		
		arrayIndex = [indexes indexGreaterThanIndex:arrayIndex];
		changeIndex++;
	}
}

- (void) forEachSetChange:(NSDictionary*) change forObject:(id) o invokeSelectorForInsertion:(SEL) insertion removal:(SEL) removal;
{
	NSKeyValueChange changeKind = L0KVOChangeKind(change);
	NSInvocation* insertionInv = nil, * removalInv = nil;
	
	// Set up the invocation stuff.
	if (changeKind == NSKeyValueChangeInsertion || changeKind == NSKeyValueChangeReplacement) {
		NSMethodSignature* insertSig = [target methodSignatureForSelector:insertion];
		insertionInv = [NSInvocation invocationWithMethodSignature:insertSig];
		
		[insertionInv setTarget:target];
		[insertionInv setSelector:insertion];
		[insertionInv setArgument:&o atIndex:2];
	}
	
	if (changeKind == NSKeyValueChangeRemoval || changeKind == NSKeyValueChangeReplacement) {
		NSMethodSignature* removeSig = [target methodSignatureForSelector:removal];
		removalInv = [NSInvocation invocationWithMethodSignature:removeSig];
		
		[removalInv setTarget:target];
		[removalInv setSelector:removal];
		[removalInv setArgument:&o atIndex:2];
	}
	
	NSSet* insertions = (changeKind == NSKeyValueChangeRemoval)? nil : L0KVOChangedValue(change);
	NSSet* removals = (changeKind == NSKeyValueChangeInsertion)? nil : L0KVOPreviousValue(change);
	
	for (id removedObject in removals) {
		[removalInv setArgument:&removedObject atIndex:3];
		[removalInv invoke];
	}
	
	for (id insertedObject in insertions) {
		[insertionInv setArgument:&insertedObject atIndex:3];
		[insertionInv invoke];
	}
}

#if __BLOCKS__
- (void) forEachArrayChange:(NSDictionary*) change invokeBlockForInsertion:(L0KVODispatcherArrayChangeBlock) insertion removal:(L0KVODispatcherArrayChangeBlock) removal replacement:(L0KVODispatcherArrayReplacementBlock) replacement;
{
	NSKeyValueChange changeKind = L0KVOChangeKind(change);
	
	NSIndexSet* indexes = L0KVOChangedIndexes(change);
	
	NSUInteger arrayIndex = [indexes firstIndex], changeIndex = 0;
	NSArray* insertions = (changeKind == NSKeyValueChangeRemoval)? nil : L0KVOChangedValue(change);
	NSArray* removals = (changeKind == NSKeyValueChangeInsertion)? nil : L0KVOPreviousValue(change);
	
	while (arrayIndex != NSNotFound) {		
		id insertedObject = [insertions objectAtIndex:changeIndex];
		id removedObject = [removals objectAtIndex:changeIndex];
		
		if (changeKind == NSKeyValueChangeRemoval || (changeKind == NSKeyValueChangeReplacement && !replacement))
			removal(removedObject, arrayIndex);			
		
		if (changeKind == NSKeyValueChangeInsertion || (changeKind == NSKeyValueChangeReplacement && !replacement))
			insertion(removedObject, arrayIndex);
		
		if (changeKind == NSKeyValueChangeReplacement && replacement)
			replacement(removedObject, insertedObject, arrayIndex);
		
		arrayIndex = [indexes indexGreaterThanIndex:arrayIndex];
		changeIndex++;
	}	
}

- (void) forEachSetChange:(NSDictionary*) change invokeBlockForInsertion:(L0KVODispatcherSetChangeBlock) insertion removal:(L0KVODispatcherSetChangeBlock) removal;
{
	NSKeyValueChange changeKind = L0KVOChangeKind(change);
	
	NSSet* insertions = (changeKind == NSKeyValueChangeRemoval)? nil : L0KVOChangedValue(change);
	NSSet* removals = (changeKind == NSKeyValueChangeInsertion)? nil : L0KVOPreviousValue(change);
	
	for (id removedObject in removals) {
		removal(removedObject);
	}
	
	for (id insertedObject in insertions) {
		insertion(insertedObject);
	}	
}
#endif

@end
