<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<PageWithHeader :actions="headerActions">
	<div class="_spacer" style="--MI_SPACER-w: 1200px;">
		<MkLoading v-if="loading"/>
		<MkResult v-else-if="space == null" type="notFound" :text="i18n.ts._spaces.notFound"/>

		<!-- 通話画面 -->
		<div v-else-if="joined" class="_gaps">
			<div :class="$style.columns">
				<div :class="$style.main" class="_gaps">
			<div :class="$style.head" class="_panel">
				<div :class="$style.title">{{ session.space?.name }}</div>
				<div :class="$style.sub">
					<MkAvatar :user="space.host" :class="$style.hostAvatar" :indicator="false"/>
					<MkUserName :user="space.host" :nowrap="true"/>
					<span>· {{ i18n.tsx._spaces.memberCount({ n: session.members.length }) }}</span>
				</div>
			</div>

			<MkInfo v-if="session.callStatus === 'connecting'">{{ i18n.ts._spaces.callConnecting }}</MkInfo>
			<MkInfo v-if="session.callStatus === 'failed'" warn>
				{{ i18n.ts._spaces.callFailed }}
				<button class="_textButton" @click="retrySpaceCall()">{{ i18n.ts.retry }}</button>
			</MkInfo>
			<MkInfo v-if="session.audioBlocked" warn>
				{{ i18n.ts._spaces.audioBlocked }}
				<button class="_textButton" @click="resumeSpaceAudio()">{{ i18n.ts._spaces.resumeAudio }}</button>
			</MkInfo>
			<MkInfo v-if="session.mutedByHost" warn closable @close="session.mutedByHost = false">{{ i18n.ts._spaces.mutedByHost }}</MkInfo>

			<div v-if="selectedShare != null" :class="$style.stage" class="_panel">
				<video ref="screenVideo" :class="$style.screen" autoplay playsinline muted :aria-label="shareLabel(selectedShare)"></video>
				<div :class="$style.shareTabs">
					<button
						v-for="share in session.screenShares"
						:key="share.id"
						class="_button"
						:class="[$style.shareTab, { [$style.shareTabActive]: share.id === selectedShare.id }]"
						:aria-pressed="share.id === selectedShare.id"
						@click="selectedShareId = share.id"
					>
						<i class="ti ti-screen-share"></i> {{ shareLabel(share) }}
					</button>
				</div>
			</div>

					<MkSpaceTile
						v-if="stageTile != null"
						:key="tileKey(stageTile)"
						:hostControls="isHost"
						:tile="stageTile"
						:removable="isHost || stageTile.creatorId === $i?.id"
						expandable
						expanded
						@remove="removeTile(stageTile)"
						@expand="stageTileId = null"
					/>

					<div :class="$style.members">
						<component
							:is="isHost && member.user.id !== $i?.id ? 'button' : 'div'"
							v-for="member in session.members"
							:key="member.user.id"
							:class="[$style.member, { [$style.speaking]: session.speakingIds.includes(member.user.id), _button: isHost && member.user.id !== $i?.id }]"
							@click="isHost && member.user.id !== $i?.id ? showMemberMenu(member, $event) : undefined"
						>
							<div :class="$style.memberAvatarWrap">
								<MkAvatar :user="member.user" :class="$style.memberAvatar" :indicator="false"/>
							</div>
							<div :class="$style.memberName"><MkUserName :user="member.user" :nowrap="true"/></div>
							<div :class="$style.memberState">
								<span v-if="member.user.id === space.hostId" :class="$style.hostBadge">{{ i18n.ts._spaces.host }}</span>
								<i v-if="session.micOnIds.includes(member.user.id)" class="ti ti-microphone" role="img" :title="i18n.ts._spaces.joinVoice" :aria-label="i18n.ts._spaces.joinVoice"></i>
								<i v-else class="ti ti-microphone-off" role="img" :title="i18n.ts._spaces.joinListen" :aria-label="i18n.ts._spaces.joinListen"></i>
							</div>
						</component>
					</div>

					<div :class="$style.controls">
						<MkButton rounded :primary="session.mode === 'voice'" :disabled="session.callStatus !== 'connected'" @click="toggleSpaceMicrophone()">
							<i :class="session.mode === 'voice' ? 'ti ti-microphone' : 'ti ti-microphone-off'"></i>
							{{ session.mode === 'voice' ? i18n.ts._spaces.micOff : i18n.ts._spaces.micOn }}
						</MkButton>
						<MkButton rounded :disabled="session.callStatus !== 'connected'" @click="toggleSpaceSpeaker()">
							<i :class="session.speakerMuted ? 'ti ti-volume-off' : 'ti ti-volume'"></i>
							{{ session.speakerMuted ? i18n.ts._spaces.speakerOn : i18n.ts._spaces.speakerOff }}
						</MkButton>
						<MkButton v-if="canShareSpaceScreen" rounded :primary="session.sharingScreen" :disabled="session.callStatus !== 'connected'" @click="toggleSpaceScreenShare()">
							<i :class="session.sharingScreen ? 'ti ti-screen-share-off' : 'ti ti-screen-share'"></i>
							{{ session.sharingScreen ? i18n.ts._spaces.stopShareScreen : i18n.ts._spaces.shareScreen }}
						</MkButton>
						<MkButton rounded danger @click="leaveSpace()"><i class="ti ti-door-exit"></i> {{ i18n.ts._spaces.leave }}</MkButton>
					</div>
				</div>

				<div :class="$style.side">
					<div :class="$style.tabs" role="tablist">
						<button v-for="t in tabs" :key="t.key" class="_button" role="tab" :aria-selected="tab === t.key" :class="[$style.tab, { [$style.tabActive]: tab === t.key }]" @click="tab = t.key">
							<i :class="t.icon"></i> {{ t.label }}
						</button>
					</div>

					<div v-show="tab === 'tiles'" class="_gaps_s" role="tabpanel">
						<MkButton v-if="canPlaceTile" rounded style="margin: 0 auto;" @click="placeTile"><i class="ti ti-plus"></i> {{ i18n.ts._spaces.placeTile }}</MkButton>
						<div v-if="sideTiles.length === 0 && stageTile == null" :class="$style.empty">{{ i18n.ts._spaces.noTiles }}</div>
						<MkSpaceTile
							v-for="tile in sideTiles"
							:key="tileKey(tile)"
							:hostControls="isHost"
							:tile="tile"
							:removable="isHost || tile.creatorId === $i?.id"
							:expandable="tile.kind !== 'play'"
							@remove="removeTile(tile)"
							@expand="stageTileId = tile.id"
						/>
					</div>

					<div v-show="tab === 'chat'" role="tabpanel">
						<div :class="$style.chat" class="_panel">
							<div :class="$style.chatTitle">{{ i18n.ts._spaces.chat }}</div>
							<div ref="chatLog" :class="$style.chatLog" role="log" aria-live="polite" :aria-label="i18n.ts._spaces.chat">
								<div v-if="session.messages.length === 0" :class="$style.chatEmpty">{{ i18n.ts._spaces.noMessages }}</div>
								<div v-for="message in session.messages" :key="message.id" :class="$style.message">
									<MkAvatar :user="message.user" :class="$style.messageAvatar" :indicator="false"/>
									<div :class="$style.messageBody">
										<div :class="$style.messageHead"><MkUserName :user="message.user" :nowrap="true"/> <MkTime :time="message.createdAt" :class="$style.messageTime"/></div>
										<div :class="$style.messageText"><Mfm :text="message.text" :plain="true" :nowrap="false"/></div>
									</div>
								</div>
							</div>
							<form :class="$style.chatForm" @submit.prevent="say">
								<MkInput v-model="draft" :class="$style.chatInput" :placeholder="i18n.ts._spaces.chatPlaceholder" :aria-label="i18n.ts._spaces.chatPlaceholder"/>
								<MkButton primary type="submit" :disabled="draft.trim() === ''" :aria-label="i18n.ts.send"><i class="ti ti-send"></i></MkButton>
							</form>
						</div>
					</div>

					<div v-show="tab === 'members'" class="_panel" :class="$style.memberList" role="tabpanel">
						<div v-for="member in session.members" :key="member.user.id" :class="$style.memberRow">
							<MkAvatar :user="member.user" :class="$style.messageAvatar" :indicator="false"/>
							<div :class="$style.memberRowName"><MkUserName :user="member.user" :nowrap="true"/></div>
							<span v-if="member.user.id === space.hostId" :class="$style.hostBadge">{{ i18n.ts._spaces.host }}</span>
							<button v-if="isHost && member.user.id !== $i?.id" class="_button" :class="$style.memberMenu" :aria-label="i18n.ts.menu" @click="showMemberMenu(member, $event)"><i class="ti ti-dots"></i></button>
						</div>
					</div>
				</div>
			</div>
		</div>

		<!-- 閉じたあとのまとめ -->
		<div v-else-if="space.endedAt != null" :class="$style.center" class="_panel _gaps">
			<div :class="$style.title">{{ space.name }}</div>
			<div>{{ i18n.ts._spaces.ended }}</div>
			<div :class="$style.sub">
				<MkAvatar :user="space.host" :class="$style.hostAvatar" :indicator="false"/>
				<MkUserName :user="space.host" :nowrap="true"/>
			</div>
			<dl :class="$style.summary">
				<dt>{{ i18n.ts._spaces.summaryParticipants }}</dt><dd>{{ i18n.tsx._spaces.memberCount({ n: space.participantCount }) }}</dd>
				<dt>{{ i18n.ts._spaces.summaryPeak }}</dt><dd>{{ i18n.tsx._spaces.memberCount({ n: space.peakCount }) }}</dd>
				<dt>{{ i18n.ts._spaces.summaryDuration }}</dt><dd>{{ i18n.tsx._spaces.minutes({ n: durationMinutes }) }}</dd>
			</dl>
			<MkButton v-if="isHost" primary rounded @click="continueSpace"><i class="ti ti-player-play"></i> {{ i18n.ts._spaces.continueSpace }}</MkButton>
		</div>

		<!-- 入り方を選ぶ -->
		<div v-else :class="$style.center" class="_panel _gaps">
			<div :class="$style.title">{{ space.name }}</div>
			<div :class="$style.sub">
				<MkAvatar :user="space.host" :class="$style.hostAvatar" :indicator="false"/>
				<MkUserName :user="space.host" :nowrap="true"/>
				<span>· {{ i18n.tsx._spaces.memberCount({ n: space.memberCount }) }}</span>
			</div>
			<MkInfo v-if="endNotice != null" warn>{{ endNotice }}</MkInfo>
			<MkInfo v-if="!space.canJoin" warn>{{ i18n.ts._spaces.cannotJoin }}</MkInfo>
			<MkLoading v-else-if="connecting"/>
			<div v-else :class="$style.joinOptions">
				<button class="_button" :class="$style.joinOption" @click="join('listen')">
					<i class="ti ti-headphones"></i>
					<span :class="$style.joinLabel">{{ i18n.ts._spaces.joinListen }}</span>
					<span :class="$style.joinDescription">{{ i18n.ts._spaces.joinListenDescription }}</span>
				</button>
				<button class="_button" :class="$style.joinOption" @click="join('voice')">
					<i class="ti ti-microphone"></i>
					<span :class="$style.joinLabel">{{ i18n.ts._spaces.joinVoice }}</span>
					<span :class="$style.joinDescription">{{ i18n.ts._spaces.joinVoiceDescription }}</span>
				</button>
			</div>
		</div>
	</div>
</PageWithHeader>
</template>

<script lang="ts" setup>
import { computed, nextTick, onActivated, onBeforeUnmount, onDeactivated, onMounted, onUnmounted, ref, useTemplateRef, watch } from 'vue';
import type * as Misskey from 'misskey-js';
import MkButton from '@/components/MkButton.vue';
import MkInfo from '@/components/MkInfo.vue';
import MkInput from '@/components/MkInput.vue';
import MkSpaceTile from '@/components/MkSpaceTile.vue';
import { getBuiltinTiles } from '@/spaces/builtin-tiles.js';
import type { MenuItem } from '@/types/menu.js';
import * as os from '@/os.js';
import { i18n } from '@/i18n.js';
import { $i } from '@/i.js';
import { definePage } from '@/page.js';
import { misskeyApi } from '@/utility/misskey-api.js';
import { openSpaceCreateDialog } from '@/utility/space.js';
import { useRouter } from '@/router.js';
import {
	attachSpaceScreen, canShareSpaceScreen, detachSpaceScreen, isInSpace, joinSpace, leaveSpace, resumeSpaceAudio, retrySpaceCall, sayInSpace,
	spaceSession as session, toggleSpaceMicrophone, toggleSpaceScreenShare, toggleSpaceSpeaker,
} from '@/utility/space-session.js';

const props = defineProps<{
	spaceId: string;
}>();

const MESSAGE_MAX_LENGTH = 2000;

const router = useRouter();

const loading = ref(true);
const fetched = ref<Misskey.entities.Space | null>(null);
const draft = ref('');
const chatLog = useTemplateRef('chatLog');

const joined = computed(() => session.status === 'joined' && isInSpace(props.spaceId));
const connecting = computed(() => session.status === 'connecting' && isInSpace(props.spaceId));
/** 参加中はセッションが持つ最新のものを、そうでなければ取ってきたものを使う */
const space = computed(() => (isInSpace(props.spaceId) ? session.space : null) ?? fetched.value);
const isHost = computed(() => space.value != null && space.value.hostId === $i?.id);
const durationMinutes = computed(() => {
	if (space.value?.endedAt == null) return 0;
	return Math.max(1, Math.round((new Date(space.value.endedAt).getTime() - new Date(space.value.createdAt).getTime()) / 60000));
});
const endNotice = computed(() => {
	if (session.lastEnd == null || session.lastEnd.spaceId !== props.spaceId) return null;
	switch (session.lastEnd.reason) {
		case 'ended': return null; // 閉じたあとはまとめの画面になる
		case 'replaced': return i18n.ts._spaces.leftBecauseReplaced;
		case 'kicked': return i18n.ts._spaces.leftBecauseKicked;
		case 'failed': return i18n.ts._spaces.leftBecauseFailed;
	}
	return null;
});

const screenVideo = useTemplateRef('screenVideo');
/** 大きく出す画面共有。選んでいなければ、いちばん新しいものを出す */
const selectedShareId = ref<string | null>(null);
const selectedShare = computed(() => {
	if (!joined.value) return null;
	return session.screenShares.find(share => share.id === selectedShareId.value) ?? session.screenShares.at(-1) ?? null;
});

function shareLabel(share: { userId: string }): string {
	const member = session.members.find(m => m.user.id === share.userId);
	return i18n.tsx._spaces.screenOf({ name: member?.user.name ?? member?.user.username ?? '?' });
}

/** ページが表に出ている間だけ true。裏に回っている間は映像をつながない */
const pageActive = ref(true);
/** いま映像をつないでいる共有と要素 */
let attachedScreen: { id: string; element: HTMLVideoElement } | null = null;

function syncScreen(): void {
	const id = selectedShare.value?.id ?? null;
	const element = screenVideo.value;
	const wanted = (pageActive.value && id != null && element != null) ? { id, element } : null;
	if (attachedScreen != null && (wanted == null || wanted.id !== attachedScreen.id || wanted.element !== attachedScreen.element)) {
		detachSpaceScreen(attachedScreen.id, attachedScreen.element);
		attachedScreen = null;
	}
	if (wanted != null && attachedScreen == null) {
		attachSpaceScreen(wanted.id, wanted.element);
		attachedScreen = wanted;
	}
}

// 大きく出す共有が変わったとき、ページが表に戻ったときに、映像をつなぎ替える。要素ができてからつなぐので、描画のあとに動かす
watch([() => selectedShare.value?.id ?? null, screenVideo, pageActive], syncScreen, { flush: 'post' });

type Tab = 'tiles' | 'chat' | 'members';
const tab = ref<Tab>('tiles');
const tabs = computed(() => [
	{ key: 'tiles' as const, icon: 'ti ti-layout-grid', label: i18n.ts._spaces.tiles },
	{ key: 'chat' as const, icon: 'ti ti-message', label: i18n.ts._spaces.chat },
	{ key: 'members' as const, icon: 'ti ti-users', label: i18n.tsx._spaces.memberCount({ n: session.members.length }) },
]);

/** 大きく出しているタイル。人ごとに選ぶ */
const stageTileId = ref<string | null>(null);
const stageTile = computed(() => session.tiles.find(tile => tile.id === stageTileId.value) ?? null);
const sideTiles = computed(() => session.tiles.filter(tile => tile.id !== stageTileId.value));

const canPlaceTile = computed(() => space.value != null && (space.value.tilePlacement === 'everyone' || isHost.value));

/** 置くタイルを選んで置く。 */
async function placeTile(ev: MouseEvent): Promise<void> {
	const target = ev.currentTarget ?? ev.target;
	// 自作タイルは、メニューを開く前に取っておく。取れなくても、きほんのタイルは置ける
	const [mine, everyones] = await Promise.all([
		misskeyApi('spaces/tile-defs/my', { limit: 30 }).catch(() => []),
		misskeyApi('spaces/tile-defs/list', { limit: 30 }).catch(() => []),
	]);
	const others = everyones.filter(def => def.userId !== $i?.id);
	const customItem = (def: Misskey.entities.SpaceTileDef): MenuItem => ({
		icon: 'ti ti-puzzle',
		text: def.name,
		caption: `@${def.user.username}`,
		action: () => { void placeCustomTile(def); },
	});
	const menu: MenuItem[] = getBuiltinTiles().map(tile => ({
		icon: tile.icon,
		text: tile.name,
		action: () => {
			void os.apiWithDialog('spaces/tiles/add', { spaceId: props.spaceId, kind: tile.kind as Misskey.entities.SpacesTilesAddRequest['kind'] });
		},
	}));
	if (mine.length > 0) menu.push({ type: 'divider' }, { type: 'label', text: i18n.ts._spaces.myTiles }, ...mine.map(customItem));
	if (others.length > 0) menu.push({ type: 'divider' }, { type: 'label', text: i18n.ts._spaces.customTiles }, ...others.map(customItem));
	menu.push({ type: 'divider' }, { type: 'link', icon: 'ti ti-layout-grid', text: i18n.ts._spaces.browseTiles, to: '/spaces/tiles' });
	os.popupMenu(menu, target);
}

/** 自作タイルを置く。外部の URL を読むタイルなら、読みに行く先を見せて、許すかどうかを聞く。 */
async function placeCustomTile(def: Misskey.entities.SpaceTileDef): Promise<void> {
	let allowedHosts: string[] = [];
	if (def.fetchHosts.length > 0) {
		const { canceled } = await os.confirm({
			type: 'question',
			title: i18n.ts._spaces.tileFetchConfirm,
			text: def.fetchHosts.join('\n'),
			okText: i18n.ts._spaces.tileFetchAllow,
			cancelText: i18n.ts._spaces.tileFetchDeny,
		});
		if (!canceled) allowedHosts = def.fetchHosts;
	}
	await os.apiWithDialog('spaces/tiles/add', { spaceId: props.spaceId, defId: def.id, allowedHosts });
}

/** 自作タイルは、作者が書き換えたあとに入り直すと、新しいコードで枠を作り直す。 */
function tileKey(tile: Misskey.entities.SpaceTile): string {
	return `${tile.id}:${tile.def?.updatedAt ?? ''}`;
}

async function removeTile(tile: Misskey.entities.SpaceTile): Promise<void> {
	const { canceled } = await os.confirm({ type: 'warning', text: i18n.ts._spaces.removeTileConfirm });
	if (canceled) return;
	await os.apiWithDialog('spaces/tiles/remove', { tileId: tile.id });
}

/** 閉じたスペースのタイルと値を引き継いで、新しいスペースをひらく。 */
async function continueSpace(): Promise<void> {
	if (space.value == null) return;
	const next = await openSpaceCreateDialog({ continueFrom: space.value });
	if (next != null) router.push('/spaces/:spaceId', { params: { spaceId: next.id } });
}

async function fetchSpace(): Promise<void> {
	try {
		fetched.value = await misskeyApi('spaces/show', { spaceId: props.spaceId });
	} catch {
		fetched.value = null;
	} finally {
		loading.value = false;
	}
}

async function join(mode: Misskey.SpaceMode): Promise<void> {
	if (space.value == null) return;
	await joinSpace(space.value, mode);
}

function say(): void {
	const text = draft.value.trim();
	if (text === '') return;
	if (text.length > MESSAGE_MAX_LENGTH) {
		os.alert({ type: 'warning', text: i18n.tsx._spaces.messageTooLong({ max: MESSAGE_MAX_LENGTH }) });
		return;
	}
	// 送れなかったときは、書いたものを消さない
	if (sayInSpace(text)) draft.value = '';
}

function showMemberMenu(member: Misskey.SpaceMember, ev: MouseEvent): void {
	os.popupMenu([{
		type: 'label',
		text: member.user.name ?? member.user.username,
	}, {
		icon: 'ti ti-microphone-off',
		text: i18n.ts._spaces.muteMember,
		action: () => {
			void os.apiWithDialog('spaces/mute', { spaceId: props.spaceId, userId: member.user.id });
		},
	}, {
		icon: 'ti ti-door-exit',
		text: i18n.ts._spaces.kickMember,
		danger: true,
		action: async () => {
			const { canceled } = await os.confirm({
				type: 'warning',
				text: i18n.tsx._spaces.kickConfirm({ name: member.user.name ?? member.user.username }),
			});
			if (canceled) return;
			await os.apiWithDialog('spaces/kick', { spaceId: props.spaceId, userId: member.user.id });
		},
	}], ev.currentTarget ?? ev.target);
}

async function rename(): Promise<void> {
	if (space.value == null) return;
	const { canceled, result } = await os.inputText({
		title: i18n.ts._spaces.rename,
		default: space.value.name,
		minLength: 1,
		maxLength: 128,
	});
	if (canceled || result == null || result.trim() === '') return;
	fetched.value = await os.apiWithDialog('spaces/update', { spaceId: props.spaceId, name: result.trim() });
}

async function changeAccess(): Promise<void> {
	if (space.value == null) return;
	const { canceled, result } = await os.select({
		title: i18n.ts._spaces.changeAccess,
		default: space.value.access,
		items: [
			{ label: i18n.ts._spaces.accessLocal, value: 'local' as const },
			{ label: i18n.ts._spaces.accessFollowers, value: 'followers' as const },
		],
	});
	if (canceled || result == null) return;
	fetched.value = await os.apiWithDialog('spaces/update', { spaceId: props.spaceId, access: result });
}

async function end(): Promise<void> {
	const { canceled } = await os.confirm({
		type: 'warning',
		text: i18n.ts._spaces.endConfirm,
	});
	if (canceled) return;
	await os.apiWithDialog('spaces/end', { spaceId: props.spaceId });
	await fetchSpace();
}

// 閉じられた・出されたあとは、取り直して画面を切り替える
watch(() => session.lastEnd, (lastEnd) => {
	if (lastEnd?.spaceId === props.spaceId) void fetchSpace();
});

// チャットは新しい発言が見えるように下へ送る
watch(() => session.messages.at(-1)?.id, async () => {
	await nextTick();
	if (chatLog.value != null) chatLog.value.scrollTop = chatLog.value.scrollHeight;
});

watch(() => props.spaceId, () => {
	loading.value = true;
	session.pageSpaceId = props.spaceId;
	void fetchSpace();
});

function closePage(): void {
	pageActive.value = false;
	if (session.pageSpaceId === props.spaceId) session.pageSpaceId = null;
}

onMounted(() => {
	session.pageSpaceId = props.spaceId;
	void fetchSpace();
});
onActivated(() => {
	session.pageSpaceId = props.spaceId;
	pageActive.value = true;
});
// 要素が残っているうちに、映像を外す
onBeforeUnmount(() => {
	if (attachedScreen != null) detachSpaceScreen(attachedScreen.id, attachedScreen.element);
	attachedScreen = null;
});
onDeactivated(closePage);
onUnmounted(closePage);

const headerActions = computed(() => (isHost.value && space.value?.endedAt == null) ? [{
	icon: 'ti ti-pencil',
	text: i18n.ts._spaces.rename,
	handler: rename,
}, {
	icon: 'ti ti-lock',
	text: i18n.ts._spaces.changeAccess,
	handler: changeAccess,
}, {
	icon: 'ti ti-square-x',
	text: i18n.ts._spaces.end,
	handler: end,
}] : []);

definePage(() => ({
	title: space.value?.name ?? i18n.ts._spaces.title,
	icon: 'ti ti-broadcast',
}));
</script>

<style lang="scss" module>
.head {
	padding: 16px 20px;
}

.center {
	padding: 28px 20px;
	text-align: center;
	align-items: center;
}

.title {
	font-size: 1.3em;
	font-weight: bold;
	overflow-wrap: anywhere;
}

.sub {
	display: flex;
	align-items: center;
	gap: 6px;
	margin-top: 4px;
	font-size: 0.9em;
	opacity: 0.8;
}

.center .sub {
	justify-content: center;
}

.hostAvatar {
	flex-shrink: 0;
	width: 20px;
	height: 20px;
}

.stage {
	overflow: hidden;
}

.screen {
	display: block;
	width: 100%;
	max-height: 70vh;
	background: var(--MI_THEME-bg);
	object-fit: contain;
}

.shareTabs {
	display: flex;
	flex-wrap: wrap;
	gap: 6px;
	padding: 8px 12px;
}

.shareTab {
	padding: 4px 12px;
	border: solid 1px var(--MI_THEME-divider);
	border-radius: 999px;
	font-size: 0.85em;
}

.shareTabActive {
	border-color: var(--MI_THEME-accent);
	color: var(--MI_THEME-accent);
}

.members {
	display: grid;
	grid-template-columns: repeat(auto-fill, minmax(96px, 1fr));
	gap: 12px;
}

.member {
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 4px;
	padding: 10px 6px;
	border-radius: var(--MI-radius);
	min-width: 0;
}

button.member:hover {
	background: var(--MI_THEME-buttonHoverBg);
}

.memberAvatarWrap {
	padding: 3px;
	border: solid 3px transparent;
	border-radius: 100%;
	transition: border-color 0.15s;
}

.speaking .memberAvatarWrap {
	border-color: var(--MI_THEME-accent);
}

.memberAvatar {
	display: block;
	width: 56px;
	height: 56px;
}

.memberName {
	max-width: 100%;
	font-size: 0.85em;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.memberState {
	display: flex;
	align-items: center;
	gap: 4px;
	font-size: 0.8em;
	opacity: 0.8;
}

.hostBadge {
	padding: 0 6px;
	border: solid 1px var(--MI_THEME-divider);
	border-radius: 999px;
}

.controls {
	display: flex;
	flex-wrap: wrap;
	justify-content: center;
	gap: 8px;
}

.columns {
	display: grid;
	grid-template-columns: minmax(0, 1fr);
	gap: var(--MI-margin);
	align-items: start;

	@container (min-width: 900px) {
		grid-template-columns: minmax(0, 3fr) minmax(320px, 2fr);
	}
}

.main,
.side {
	min-width: 0;
}

.side {
	display: flex;
	flex-direction: column;
	gap: 10px;
}

.tabs {
	display: flex;
	gap: 4px;
	padding: 4px;
	border-radius: 999px;
	background: var(--MI_THEME-panel);
}

.tab {
	flex: 1;
	padding: 6px 8px;
	border-radius: 999px;
	font-size: 0.9em;
	white-space: nowrap;
	overflow: hidden;
	text-overflow: ellipsis;
}

.tabActive {
	background: var(--MI_THEME-accentedBg);
	color: var(--MI_THEME-accent);
	font-weight: bold;
}

.empty {
	padding: 16px;
	text-align: center;
	opacity: 0.6;
	font-size: 0.9em;
}

.memberList {
	padding: 8px 12px;
}

.memberRow {
	display: flex;
	align-items: center;
	gap: 8px;
	padding: 6px 0;
	min-width: 0;
}

.memberRowName {
	flex: 1;
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
	white-space: nowrap;
}

.memberMenu {
	flex-shrink: 0;
	width: 28px;
	height: 28px;
	border-radius: 100%;

	&:hover {
		background: var(--MI_THEME-buttonHoverBg);
	}
}

.chat {
	display: flex;
	flex-direction: column;
	padding: 12px 16px;
}

.chatTitle {
	font-weight: bold;
	margin-bottom: 8px;
}

.chatLog {
	height: 280px;
	overflow-y: auto;
	display: flex;
	flex-direction: column;
	gap: 10px;
}

.chatEmpty {
	margin: auto;
	opacity: 0.6;
	font-size: 0.9em;
}

.message {
	display: flex;
	gap: 8px;
	min-width: 0;
}

.messageAvatar {
	flex-shrink: 0;
	width: 32px;
	height: 32px;
}

.messageBody {
	min-width: 0;
}

.messageHead {
	font-size: 0.85em;
	font-weight: bold;
}

.messageTime {
	font-weight: normal;
	opacity: 0.6;
	margin-left: 4px;
}

.messageText {
	overflow-wrap: anywhere;
	white-space: pre-wrap;
}

.chatForm {
	display: flex;
	align-items: center;
	gap: 8px;
	margin-top: 10px;
}

.chatInput {
	flex: 1;
}

.summary {
	display: grid;
	grid-template-columns: auto auto;
	gap: 4px 16px;
	margin: 0;
	text-align: left;

	dt {
		opacity: 0.7;
	}

	dd {
		margin: 0;
		font-weight: bold;
	}
}

.joinOptions {
	display: grid;
	grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
	gap: 10px;
	width: 100%;
}

.joinOption {
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 4px;
	padding: 18px 12px;
	border: solid 1px var(--MI_THEME-divider);
	border-radius: var(--MI-radius);
	font-size: 1.4em;

	&:hover {
		border-color: var(--MI_THEME-accent);
		color: var(--MI_THEME-accent);
	}
}

.joinLabel {
	font-size: 0.75em;
	font-weight: bold;
}

.joinDescription {
	font-size: 0.55em;
	opacity: 0.7;
}
</style>
