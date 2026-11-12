--!strict
-- Shared data contracts; authoritative state is owned by server services.
export type Song = {Backend: string?, Track: string?, Video: string?, SoundId: string?, Template: string?, Volume: number?, PlaybackSpeed: number?, StartTime: number?, StartDelay: number?, LoopStartTime: number?, LoopEndTime: number?}
export type EmoteDefinition = {
    Name: string, Order: number, Loop: string?, Loop1: string?, Loop2: string?, Intro: string?,
    Song: Song?, Default: boolean?, Exclusive: boolean?, Syncable: boolean?, Traversal: boolean?,
    Speed: number?, AnimSpeed: number?, SyncMode: string?, MaxParticipants: number?, SwapRoles: boolean?,
    Video: boolean?, Category: string?, DisableEnvironmentCollision: boolean?, DisableEmoteCamera: boolean?, AfterImage: {[string]: any}?,
}
export type InventoryData = {OwnedEmotes: {string}, EquippedSlots: {[string]: string}}
export type SettingDefinition = {Id: string, Type: string, Name: string, Default: any, Min: number?, Max: number?, Step: number?}
export type EmoteSession = {Id: number, Player: Player, Character: Model, Name: string, Data: EmoteDefinition, StartTime: number, Host: Model?}
export type Effect = {Start: (Player, Model, any) -> any, Stop: (any) -> ()}
export type Lifecycle = {Init: (any) -> (), Start: () -> (), Destroy: () -> ()}
return {}

