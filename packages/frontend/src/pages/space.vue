<!--
SPDX-FileCopyrightText: syuilo and misskey-project
SPDX-License-Identifier: AGPL-3.0-only
-->

<template>
<PageWithHeader :actions="headerActions">
	<div class="_spacer" style="--MI_SPACER-w: 800px;">
		<MkLoading v-if="loading"/>
		<MkResult v-else-if="space == null" type="notFound" :text="i18n.ts._spaces.notFound"/>

		<!-- 通話画面 -->
		<div v-else-if="joined" class="_gaps">
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
import * as os from '@/os.js';
import { i18n } from '@/i18n.js';
import { $i } from '@/i.js';
import { definePage } from '@/page.js';
import { misskeyApi } from '@/utility/misskey-api.js';
import {
	attachSpaceScreen, canShareSpaceScreen, detachSpaceScreen, isInSpace, joinSpace, leaveSpace, resumeSpaceAudio, retrySpaceCall, sayInSpace,
	spaceSession as session, toggleSpaceMicrophone, toggleSpaceScreenShare, toggleSpaceSpeaker,
} from '@/utility/space-session.js';

const props = defineProps<{
	spaceId: string;
}>();

const MESSAGE_MAX_LENGTH = 2000;

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
