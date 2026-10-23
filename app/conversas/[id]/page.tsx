"use client";
import { useParams } from "next/navigation";
import { ChatPane } from "../../../components/chat/ChatPane";

export default function Conversa() {
  const { id } = useParams<{ id: string }>();
  return <ChatPane key={id} id={id} />;
}
