import { createRouter, createWebHistory } from 'vue-router';
import PostsView from '../views/PostsView.vue';
import PostView from '../views/PostView.vue';
import AdminView from '../views/AdminView.vue';
import AdminFormView from '../views/AdminFormView.vue';

const routes = [
  { path: '/', name: 'posts', component: PostsView },
  { path: '/post/:id', name: 'post', component: PostView },
  { path: '/admin', name: 'admin', component: AdminView },
  { path: '/admin/new', name: 'admin-new', component: AdminFormView },
  { path: '/admin/:id', name: 'admin-edit', component: AdminFormView }
];

export default createRouter({
  history: createWebHistory(),
  routes
});
