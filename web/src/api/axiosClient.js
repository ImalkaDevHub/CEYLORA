import axios from 'axios';

const axiosClient = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL,
});

// Attach the token to every request once we're logged in
axiosClient.interceptors.request.use((config) => {
  const token = sessionStorage.getItem('ceylora_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export default axiosClient;
